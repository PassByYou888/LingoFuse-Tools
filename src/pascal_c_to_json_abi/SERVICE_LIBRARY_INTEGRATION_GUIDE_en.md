# SERVICE Library Integration Guide

> *English translation of [SERVICE_LIBRARY_INTEGRATION_GUIDE.md](SERVICE_LIBRARY_INTEGRATION_GUIDE.md).*

> This document gives the integration method for the **Service library (service side)** in **each target language**.
>
> **What the Service library is** — the Service library is the "service side" artifact. It registers a group of local functions as **LingoFuse Call APIs**, receives JSON requests from the mesh, calls the internal business logic, and returns the result as a JSON response.
>
> **Three universal prerequisites for the Service library**:
>
> 1. **The LingoFuse native library must be used** (`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`) together with `z_ipc_*`.
> 2. **The LingoFuse language binding must be used** (`lingofuse_import` / the `lingofuse` Python package / `LingoFuse.hpp` / ...).
> 3. **The "three-piece" initialization must be completed**: `prepareService` → `prepareClient` → `prepareDone`.
>
> **The core question of this document: does the Service need to go through the bridge?**
>
> **Answer: no.** The Service is a node of the LingoFuse mesh. It listens on a mesh endpoint directly and **does not go through the bridge**. The bridge (`bridge.py` / `bridge.exe`) only serves the direction **call side → service side**.
>
> In other words:
>
> - **The Service** is the "callee" — it listens on the mesh, waiting for the bridge to turn an HTTP request into an LF_Call and deliver it.
> - **The bridge** is the "forwarder" — it turns the call side's HTTP request into an LF_Call and sends it to the Service on the mesh.
> - **The Service is upstream of the bridge, not downstream. The Service does not depend on the bridge, but the bridge depends on the Service.**
>
> **Therefore**: when starting the Service, **the bridge does not need to be running at all**. The Service can start and be tested on its own (for example in `--smoke` mode). As long as the Service and the bridge use **the same endpoint**, the bridge will find the Service once it comes online.
>
> **Three important facts about language support**:
>
> 1. **The Service side must use the LingoFuse native library.** All 16+ languages that support the Service side (Pascal / Python / C++ / C# / Node.js / TypeScript / Rust / Go / Java / Dart / Swift / Ruby / Zig / Erlang / Fortran / Julia / R) depend on the LingoFuse native library.
> 2. **Three languages have no service side**: JavaScript (browser), PHP and Delphi. Those three can only be Call.
> 3. **Platform support is limited by the LingoFuse native library**: Windows / Linux / macOS (desktop / server). **iOS / Android / WASM / embedded are not supported** — even if the language itself supports those platforms.

---

## Table of contents

1. [Positioning of the Service library](#1-positioning-of-the-service-library)
2. [The Service does not need to go through the bridge](#2-the-service-does-not-need-to-go-through-the-bridge)
3. [The Service's three-piece initialization](#3-the-services-three-piece-initialization)
4. [Language and platform support for the Service](#4-language-and-platform-support-for-the-service)
5. [Detailed integration per language](#5-detailed-integration-per-language)
   - [5.1 Pascal](#51-pascal)
   - [5.2 Python](#52-python)
   - [5.3 C++](#53-c)
   - [5.4 C#](#54-c)
   - [5.5 Node.js](#55-nodejs)
   - [5.6 TypeScript](#56-typescript)
   - [5.7 Rust](#57-rust)
   - [5.8 Go](#58-go)
   - [5.9 Java](#59-java)
   - [5.10 Dart](#510-dart)
   - [5.11 Swift](#511-swift)
   - [5.12 Ruby](#512-ruby)
   - [5.13 Zig](#513-zig)
   - [5.14 Erlang](#514-erlang)
   - [5.15 Fortran](#515-fortran)
   - [5.16 Julia](#516-julia)
   - [5.17 R](#517-r)
6. [Languages with no service side](#6-languages-with-no-service-side)
7. [Platform and OS support matrix](#7-platform-and-os-support-matrix)
8. [Cross-comparison quick reference](#8-cross-comparison-quick-reference)
9. [Common integration problems](#9-common-integration-problems)

---

## 1. Positioning of the Service library

### 1.1 Service library = the service side

A complete interface pair consists of **Service (service side)** and **Call (call side)**:

| Side | Responsibility | Goes through the bridge |
|----|------|:----------:|
| **Service** | Registers functions as LingoFuse Call APIs, receives JSON requests and returns JSON responses | ❌ **no** |
| **Call** | Converts local function calls into requests to the bridge program, then converts responses back to local types | ✅ **mandatory** |

**The key asymmetry**:

- **The Service does not depend on the bridge.** It only depends on the LingoFuse mesh.
- **The Call depends on the bridge.** It reaches the Service through the bridge.

### 1.2 Artifact naming

```
<UnitName>_http_json_service_<lang_suffix>.<ext>
```

| Language | Service library file name |
|------|-----------------|
| Pascal | `<Unit>_http_json_service_unit.pas` |
| Python | `<Unit>_http_json_service.py` |
| C++ | `<Unit>_http_json_service.hpp` + `<Unit>_http_json_service.cpp` |
| C# | `<Unit>_http_json_service.cs` |
| Node.js | `<Unit>_http_json_service_node.js` |
| TypeScript | `<Unit>_http_json_service.ts` |
| Rust | `<Unit>_http_json_service_rs.rs` |
| Go | `<Unit>_http_json_service_go.go` |
| Java | `HttpJsonService.java` |
| Dart | `<Unit>_http_json_service.dart` |
| Swift | `<Unit>_http_json_service_swift.swift` |
| Ruby | `<Unit>_http_json_service.rb` |
| Zig | `<Unit>_http_json_service_zig.zig` |
| Erlang | `<Unit>_http_json_service.erl` |
| Fortran | `<Unit>_http_json_service_mod.f90` |
| Julia | `<Unit>_http_json_service.jl` |
| R | `<Unit>_http_json_service.R` + `<Unit>_http_json_service_impl.R` |

**Languages with no service side**: JavaScript (browser), PHP, Delphi.

### 1.3 The interface the Service library exposes

The Service library in each language provides:

- **a registration entry** (a set of `registerAllAPIs` / `register_all_apis` / `RegisterAPIs` / `registerCall` calls).
- **an App creation entry** (`CreateAndRegisterHTTPJsonApp` / `createAndRegisterHttpJsonApp` / `create_and_register_http_json_app` / `App(...)` etc.).
- **a `main` / `run_service` / `main()` entry** (directly runnable as an executable).
- **an `internal_call_<Api>` stub for each supported API** (the user fills in the business logic).

### 1.4 Differences between Service and Call

| Dimension | Service | Call |
|------|---------|------|
| **Goes through the bridge** | ❌ no | ✅ mandatory |
| **Needs the LingoFuse native library** | ✅ mandatory | depends on the language (mode A does not) |
| **Needs a LingoFuse language binding** | ✅ mandatory | depends on the language |
| **Registers APIs** | ✅ yes (`LF_RegisterCallEx` / `registerCall`) | ❌ no |
| **Listens on an endpoint** | ✅ yes (`prepareService`) | ❌ no (only `prepareClient`) |
| **Creates an App** | ✅ yes (`LF_CreateAppEx` / `App(...)`) | ❌ no |
| **Core user code** | the `internal_call_<Api>` stub (business logic) | calling the generated function (business logic lives elsewhere) |
| **Platform support** | limited by the LingoFuse native library | limited by the language's HTTP client (mode A is wider) |

---

## 2. The Service does not need to go through the bridge

### 2.1 Complete topology

```
       ┌──────────────────────────────────────────────────┐
       │  Service process                                  │
       │  ─ listens on ipc:<Unit>_http_json (prepareService)│
       │  ─ creates the App (LF_CreateAppEx)               │
       │  ─ registers the APIs (LF_RegisterCallEx)         │
       │  ─ connects to the same endpoint as a client      │
       │    (prepareClient)                                │
       │  ─ starts the mesh (prepareDone)                  │
       └──────────────────────────────────────────────────┘
                          ▲
                          │ LF_Call (inside the mesh)
                          │
       ┌──────────────────────────────────────────────────┐
       │  Bridge process (bridge.py)                       │
       │  ─ connects to the same endpoint as a client      │
       │  ─ registers the __lf_outbound_post__ forwarding  │
       │    API                                            │
       └──────────────────────────────────────────────────┘
                          ▲
                          │ HTTP POST
                          │
       ┌──────────────────────────────────────────────────┐
       │  Call process (any language)                      │
       │  ─ HTTP POSTs directly to bridge:8081             │
       │  ─ or calls __lf_outbound_post__ through LingoFuse│
       └──────────────────────────────────────────────────┘
```

### 2.2 Three key facts

1. **The Service does not call the bridge.** It only does `prepareService` + `prepareClient` + `prepareDone`, then waits for the mesh to deliver LF_Calls.
2. **The bridge actively connects to the endpoint the Service is on.** The bridge is the client and the Service is the listener. Once the bridge comes online it discovers the Service automatically.
3. **Service first, bridge later is perfectly fine.** The bridge plays the "client" role, so it can start later than the Service. Conversely, the Service starting later than the bridge is also fine — the bridge rediscovers the Service on the next broadcast round.

### 2.3 The Service can run standalone

**`--smoke` mode**: the Service does not start the mesh at all; it only creates the `App` in-process and calls each API directly through `local_call`.

| Language | `--smoke` mode entry |
|------|-------------------|
| Pascal | `./<Unit>_http_json_service_main_test___ --smoke` |
| Python | `python3 <Unit>_http_json_service_main_test___.py --smoke` |
| C++ | none (C++ has no smoke subcommand) |
| C# | `dotnet run -- --smoke` |
| Node.js | `node <Unit>_http_json_service_main_test___.js --smoke` |
| TypeScript | `tsx <Unit>_http_json_service_main_test___.ts --smoke` |
| Rust | just `cargo run` (no smoke subcommand; write your own) |
| Go | `go test -v` |
| Java | `java HttpJsonServiceTest --smoke` |
| Dart | none (Dart has no smoke subcommand) |
| Swift | `swift <Unit>_http_json_service_main_test___.swift --smoke` |
| Ruby | `ruby <Unit>_http_json_service_main_test___.rb --smoke` |
| Zig | none (Zig has no smoke subcommand) |
| Erlang | `escript <Unit>_http_json_service_main_test___.escript --smoke` |
| Fortran | `./service_test.exe --smoke` |
| Julia | `julia <Unit>_http_json_service_main_test___.jl --smoke` |
| R | none (R has no smoke subcommand; use `parse()` as a syntax check) |

**`--smoke` mode needs no bridge at all**, because it never touches the mesh.

### 2.4 The only link between the Service and the bridge

**They share the same endpoint string**:

```
ipc:<UnitName>_http_json
```

- The Service listens on it in `prepareService(endpoint, endpoint)`.
- The bridge connects to it via `bridge.py --endpoint <endpoint>`.

**The strings must match exactly.** Otherwise they cannot find each other.

---

## 3. The Service's three-piece initialization

All 16+ languages' service sides follow the same initialization pattern:

```
Step 1: prepareService(endpoint, endpoint)
    ─ listen on the mesh endpoint
    ─ become a beacon

Step 2: create the App + register the APIs
    ─ App = LF_CreateAppEx(name, desc)
    ─ for each API: LF_RegisterCallEx(App, api_name, desc, trigger, callback)
    ─ or the language binding's equivalent

Step 3: prepareClient(endpoint, App)
    ─ also connect to the same endpoint as a client
    ─ so other mesh nodes can route to it

Step 4: prepareDone()
    ─ start the mesh event loop
    ─ returns 1 on a successful first start
```

**Why `prepareClient` in addition to `prepareService`?** Because LingoFuse's routing model requires that "the App being called must be visible on the mesh as a client". `prepareService` only "opens the port"; `prepareClient` is what "joins the mesh". Using the same endpoint for both creates a "self-connection".

### 3.1 The order cannot be reversed

| Step | Must come before | Reason |
|------|----------|------|
| `prepareService` | position 1 | without a listening port, the later `prepareClient` has nowhere to connect |
| App creation + API registration | before `prepareClient` | registration must complete before the client joins the mesh, otherwise the mesh does not see the APIs |
| `prepareClient` | before `prepareDone` | `prepareDone` starts the mesh loop |
| `prepareDone` | last | once started, new APIs cannot be registered |

### 3.2 Shutdown order

```
Step 1: exitMainThread()       ─ stop the mesh event loop
Step 2: FreeApp(app)           ─ release the App (which unregisters the APIs)
Step 3: shutdown()             ─ release the LingoFuse native library
```

**The order cannot be reversed**: stop the mesh, then unregister the APIs, then release the library.

---

## 4. Language and platform support for the Service

### 4.1 Languages that support the Service

| # | Language | Needs the LingoFuse native library | Needs a LingoFuse language binding |
|:-:|------|:------------------------:|:---------------------------:|
| 1 | Pascal | ✅ | ✅ `lingofuse_import` |
| 2 | Python | ✅ | ✅ the `lingofuse` Python package |
| 3 | C++ | ✅ | ✅ `LingoFuse.hpp` + `lf_io.hpp` |
| 4 | C# | ✅ | ✅ the `LingoFuse` .NET binding |
| 5 | Node.js | ✅ | ✅ `lingofuse-js` |
| 6 | TypeScript | ✅ | ✅ `lingofuse-ts` |
| 7 | Rust | ✅ | ✅ the `lingofuse` crate |
| 8 | Go | ✅ | ✅ `github.com/PassByYou888/LingoFuse/go` |
| 9 | Java | ✅ | ✅ the `lingofuse` Java package |
| 10 | Dart | ✅ | ✅ the `lingofuse` Dart package |
| 11 | Swift | ✅ | ✅ the `lingofuse` Swift binding |
| 12 | Ruby | ✅ | ✅ the `lingofuse` gem |
| 13 | Zig | ✅ | ✅ the `lingofuse` Zig binding |
| 14 | Erlang | ✅ | ✅ the `lingofuse` Erlang binding |
| 15 | Fortran | ✅ | ✅ `lf_fortran_mod` |
| 16 | Julia | ✅ | ✅ the `LingoFuse` Julia binding |
| 17 | R | ✅ | ✅ the `lingofuse` R package |

**All 17 languages depend on the LingoFuse native library. There is no "pure HTTP Service" mode** — the service side is always a LingoFuse mesh node.

### 4.2 Languages that do not support the Service

| Language | Reason |
|------|------|
| **JavaScript (browser)** | a browser cannot be a LingoFuse mesh node (it cannot load a native library) |
| **PHP** | PHP has no LingoFuse native library support |
| **Delphi** | Delphi's `System.Net.HttpClient` is a pure HTTP client with no LingoFuse native library binding |

Those three languages **can only be Call** (see `CALL_LIBRARY_INTEGRATION_GUIDE.md`).

### 4.3 Platforms and operating systems

**The platform support of all 17 languages' service sides = the support range of the LingoFuse native library.**

| OS | Supported | Notes |
|----------|:----:|------|
| **Windows (x86 / x64 / arm64)** | ✅ | needs `LingoFuse64.dll` + `z_ipc_64.dll` |
| **Linux (x64 / arm64)** | ✅ | needs `liblingofuse.so` + `libz_ipc_64.so` |
| **macOS (x64 / arm64)** | ✅ | needs `liblingofuse.dylib` |
| **iOS / iPadOS** | ❌ | not supported by the LingoFuse native library |
| **Android** | ❌ | not supported by the LingoFuse native library |
| **WASM** | ❌ | not supported by the LingoFuse native library |
| **Embedded (ARM Cortex-M etc.)** | ❌ | not supported by the LingoFuse native library |
| **FreeBSD / OpenBSD / NetBSD** | ❌ | not supported by the LingoFuse native library |

**Key conclusion**: the Service can only run on **desktop / server platforms**. **Mobile / embedded / WASM cannot run a Service.** If you need to expose an interface to a mobile client, the Service must be deployed on a server and the mobile client acts as a Call through the bridge.

### 4.4 Additional requirements per language's service side

| Language | Additional requirements |
|------|----------|
| Pascal | FPC 3.2+ or Delphi 11+ |
| Python | Python 3.8+ |
| C++ | C++17, CMake 3.15+ |
| C# | .NET 8.0+ |
| Node.js | Node 18+ |
| TypeScript | TS 5.0+, `tsx`, Node 18+ |
| Rust | Rust 1.70+ |
| Go | Go 1.21+ (the service side needs `CGO_ENABLED=1`) |
| Java | JDK 11+ |
| Dart | Dart 3.0+ |
| Swift | Swift 5.9+, macOS 12+ / Linux |
| Ruby | Ruby 2.7+ / 3.0+ (the gem needs a C extension toolchain) |
| Zig | Zig 0.13+ |
| Erlang | Erlang/OTP 25+ |
| Fortran | gfortran 9+ / ifort / flang |
| Julia | Julia 1.9+, **`--threads=2` mandatory** |
| R | R 4.0+ |

---

## 5. Detailed integration per language

### 5.1 Pascal

#### 5.1.1 Artifacts

```
<Unit>_http_json_service_unit.pas
```

#### 5.1.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| `lingofuse_import.pas` | LingoFuse distribution | ✅ |
| `Z.Core`, `Z.PascalStrings`, `Z.UPascalStrings`, `Z.UnicodeMixedLib`, `Z.Json` | the Z framework | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` / `libz_ipc_64.so` | LingoFuse distribution | ✅ (runtime) |

#### 5.1.3 Platform

- **Compiler**: FPC 3.2+ / Delphi 11+.
- **OS**: Windows (x86/x64/arm64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.1.4 Initialization

```pascal
uses
  lingofuse_import,
  <Unit>_http_json_service_unit;

var
  App: TAppHnd___;
begin
  // 1. Load the LingoFuse native library
  if LF_LoadLibrary() <> 1 then
  begin
    WriteLn('Failed to load LingoFuse');
    Halt(1);
  end;

  // 2. Listen on the endpoint
  LF_PrepareServiceEx('ipc:<Unit>_http_json', 'ipc:<Unit>_http_json');

  // 3. Create the App + register the APIs
  App := CreateAndRegisterHTTPJsonApp;
  if App = nil then
  begin
    WriteLn('Failed to create app');
    Halt(1);
  end;

  // 4. Connect to the same endpoint as a client
  LF_PrepareClientEx('ipc:<Unit>_http_json', App);
  if LF_PrepareDone() <> 1 then
  begin
    WriteLn('Failed to prepare');
    Halt(1);
  end;

  WriteLn('Service ready. Press Enter to stop.');
  ReadLn;
end.
```

#### 5.1.5 Filling in the business logic

**In the generated `<Unit>_http_json_service_unit.pas`**, find the `internal_call_<Api>` stub and replace `TODO` with the real call:

```pascal
function internal_call_Add_Add(a: Int64; b: Int64): Int64;
begin
  // TODO: call the real function, for example:
  //   Result := Add(a, b);
  Result := 0;  // ← replace this
end;
```

**Recommended practice**: put the business logic in a separate unit `CalculatorImpl.pas`, and let the stub only do `Result := CalculatorImpl.Add(a, b);`. That way the business logic survives regenerating the service unit.

#### 5.1.6 Shutdown

```pascal
LF_ExitMainThread;
LF_FreeApp(App);
LF_Shutdown;
```

#### 5.1.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `LF_PrepareServiceEx` fails | the endpoint is already taken | change the endpoint or kill the old process |
| `LF_PrepareDone` returns 0 | already called in this process | restart the process |
| `no found app("<Unit>")` (reported by the bridge) | the Service is not running | start the Service |

---

### 5.2 Python

#### 5.2.1 Artifacts

```
<Unit>_http_json_service.py
```

#### 5.2.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| the `lingofuse` Python package | LingoFuse distribution | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| Python 3.8+ | — | ✅ |

#### 5.2.3 Platform

- **Runtime**: Python 3.8+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.2.4 Initialization

**The generated `main()` already contains the complete initialization flow**, so just run it:

```bash
python3 <Unit>_http_json_service.py
```

**Or initialize explicitly in your own code**:

```python
from lingofuse._lf_native import (
    LF_ResetPrepare, LF_PrepareService, LF_PrepareClient, LF_PrepareDone,
    LF_CreateAppEx, LF_RegisterCallEx, LF_ExitMainThread, LF_Shutdown
)
from lingofuse.lf_io import cstr

ENDPOINT = "ipc:<Unit>_http_json"

# 1. Configure
LF_SetOptionEx("Wait_Connection_ReadyOk", "False")
LF_SetOptionEx("Overlap_Connection", "True")
LF_ResetPrepare()

# 2. Listen on the endpoint
LF_PrepareService(cstr(ENDPOINT), cstr(ENDPOINT))

# 3. Create the App + register the APIs
app = LF_CreateAppEx(cstr("<Unit>"), cstr("HTTP/JSON service for <Unit>"))
LF_RegisterCallEx(app, cstr("Add"), cstr("Adds two integers"), nil, callback_add)
LF_RegisterCallEx(app, cstr("Sub"), cstr("Subtracts b from a"), nil, callback_sub)

# 4. Connect to the same endpoint as a client
LF_PrepareClient(cstr(ENDPOINT), app)
if LF_PrepareDone() != 1:
    raise RuntimeError("prepare_done failed")

# 5. Wait for Ctrl+C
import signal
signal.pause()

# 6. Shutdown
LF_ExitMainThread()
app.free()
LF_Shutdown()
```

#### 5.2.5 Filling in the business logic

**In the generated `<Unit>_http_json_service.py`**, find the `internal_call_<Api>` stub:

```python
def internal_call_Add(a: int, b: int) -> int:
    """
    HTTP/JSON API: Add.
    TODO: replace the body with a call to the real implementation.
    Suggested call: Add(a, b)
    """
    # TODO: implement this stub.
    return 0  # ← replace this
```

**Recommended practice**: create a `calculator_impl.py` and let the stub do `from calculator_impl import add` + `return add(a, b)`.

#### 5.2.6 Shutdown

```python
LF_ExitMainThread()
app.free()
LF_Shutdown()
```

#### 5.2.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `ModuleNotFoundError: lingofuse` | the LingoFuse Python package is not installed | install the LingoFuse distribution |
| `prepare_service` returns -1 | the endpoint is already taken | change the endpoint or kill the old process |
| `prepare_done` returns 0 | already called in this process | restart the process |

---

### 5.3 C++

#### 5.3.1 Artifacts

```
<Unit>_http_json_service.hpp
<Unit>_http_json_service.cpp
```

#### 5.3.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| `LingoFuse.h`, `LingoFuse.c` | LingoFuse distribution | ✅ |
| `LingoFuse.hpp`, `lf_io.hpp` | LingoFuse distribution | ✅ |
| `json.hpp` (nlohmann) | shipped with the LingoFuse distribution or obtained separately | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| a C++17 compiler | — | ✅ |
| CMake 3.15+ | — | recommended |

#### 5.3.3 Platform

- **Compiler**: MSVC 2019+ / g++ 9+ / clang++ 10+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.3.4 Initialization

**The generated `run_service()` already contains the complete flow**, so just call it from `main()`:

```bash
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
./build/<Unit>_http_json_service
```

**The core flow of `run_service()`**:

```cpp
int run_service() {
    // 1. Load the LingoFuse native library (RAII)
    lingofuse::LibraryLoader loader;

    // 2. Configure
    lingofuse::setOption("Wait_Connection_ReadyOk", "False");
    lingofuse::setOption("Overlap_Connection", "True");
    lingofuse::resetPrepare();

    // 3. Listen on the endpoint
    if (lingofuse::prepareService("<Unit>_http_json_endpoint",
                                  "<Unit>_http_json_endpoint") < 0) {
        return 1;
    }

    // 4. Create the App + register the APIs + connect to the same
    //    endpoint as a client
    {
        lingofuse::App app("Calculator", "HTTP/JSON service for Calculator");
        if (!app) return 1;

        register_all_http_json_apis(app);

        if (lingofuse::prepareClient("<Unit>_http_json_endpoint", app.get()) < 0) {
            return 1;
        }

        if (lingofuse::prepareDone() != 1) {
            return 1;
        }

        std::cout << "[OK] Service ready." << std::endl;

        // wait for Ctrl+C
        std::signal(SIGINT, _on_signal);
        while (!g_stop_requested.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }

        lingofuse::exitMainThread();
    }
    // the App destructor frees the app automatically

    lingofuse::shutdown();
    return 0;
}
```

#### 5.3.5 Filling in the business logic

**In the generated `<Unit>_http_json_service.cpp`**, find the `internal_call_<Api>` stub:

```cpp
std::int64_t internal_call_Add(std::int64_t a, std::int64_t b) {
    // TODO: implement this stub.
    // Suggested call: Add(a, b);
    return 0;  // ← replace this
}
```

**Recommended practice**: create `calculator_impl.hpp` / `.cpp` and let the stub do `return calculator_impl::add(a, b);`.

#### 5.3.6 Shutdown

```cpp
lingofuse::exitMainThread();
// the App destructor frees the app automatically
lingofuse::shutdown();
// the LibraryLoader destructor calls LF_FreeLibrary automatically
```

#### 5.3.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `LF_PrepareService failed` | the endpoint is already taken | change the endpoint or kill the old process |
| `LF_PrepareDone failed` | already called in this process | restart the process |
| the linker cannot find `LingoFuse` | the DLL was not copied | copy the DLL next to the executable |

---

### 5.4 C#

#### 5.4.1 Artifacts

```
<Unit>_http_json_service.cs
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
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.4.4 Initialization

**The generated `Service.RunService()` already contains the complete flow**:

```csharp
// your Program.cs
using <Unit>_http_json_service;

class Program
{
    static int Main(string[] args) => Service.RunService();
}
```

**The core flow of `RunService()`**:

```csharp
public static int RunService()
{
    // 1. Configure
    Framework.SetOption("Wait_Connection_ReadyOk", "False");
    Framework.SetOption("Overlap_Connection", "True");
    Framework.ResetPrepare();

    // 2. Listen on the endpoint
    if (Framework.PrepareService(AppInfo.Endpoint, AppInfo.Endpoint) < 0)
    {
        Console.Error.WriteLine("[FATAL] PrepareService failed");
        return 1;
    }

    // 3. Create the App + register the APIs + connect to the same
    //    endpoint as a client
    AppHandle? app = null;
    try
    {
        app = new AppHandle(AppInfo.Name, AppInfo.Desc);
        RegisterAPIs(app);

        if (Framework.PrepareClient(AppInfo.Endpoint, app) < 0)
        {
            Console.Error.WriteLine("[FATAL] PrepareClient failed");
            return 1;
        }

        if (Framework.PrepareDone() != 1)
        {
            Console.Error.WriteLine("[FATAL] PrepareDone failed");
            return 1;
        }

        Console.WriteLine("[OK] Service ready. Press Ctrl+C to stop.");

        var stop = new ManualResetEventSlim(false);
        Console.CancelKeyPress += (s, e) => { e.Cancel = true; stop.Set(); };
        while (!stop.IsSet) Thread.Sleep(500);

        return 0;
    }
    finally
    {
        // 4. Shutdown (the order cannot be reversed)
        try { NetworkEvents.Clear(); } catch { }
        try { Framework.ExitMainThread(); } catch { }
        try { app?.Dispose(); } catch { }
        try { Framework.Shutdown(); } catch { }
    }
}
```

#### 5.4.5 Filling in the business logic

**In the generated `<Unit>_http_json_service.cs`**, find each stub of the `InternalCalls` class:

```csharp
public static class InternalCalls
{
    public static long Add(long a, long b)
    {
        // TODO: replace the body with a call to the real implementation.
        // Suggested call: Add(a, b);
        return 0;  // ← replace this
    }
}
```

**Recommended practice**: create `CalculatorImpl.cs` and let the stub do `return CalculatorImpl.Add(a, b);`.

#### 5.4.6 Shutdown

```csharp
try { NetworkEvents.Clear(); } catch { }
try { Framework.ExitMainThread(); } catch { }
try { app?.Dispose(); } catch { }
try { Framework.Shutdown(); } catch { }
```

#### 5.4.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `DllNotFoundException: LingoFuse64` | the DLL was not copied | copy it into the bin directory |
| `Could not load type 'lingofuse.AppHandle'` | the LingoFuse.dll reference is missing | `dotnet add reference` |
| `PrepareService failed` | the endpoint is already taken | change the endpoint or kill the old process |

---

### 5.5 Node.js

#### 5.5.1 Artifacts

```
<Unit>_http_json_service_node.js
```

#### 5.5.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| `lingofuse-js` | npm | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| Node.js 18+ | — | ✅ |

#### 5.5.3 Platform

- **Runtime**: Node.js 18+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.5.4 Initialization

**The generated `main()` already contains the complete flow**:

```bash
node <Unit>_http_json_service_node.js
```

**The core flow of `main()`**:

```javascript
function main() {
    // 1. Configure
    framework.setOption('Wait_Connection_ReadyOk', 'False');
    framework.setOption('Overlap_Connection', 'True');
    framework.resetPrepare();

    // 2. Listen on the endpoint
    if (framework.prepareService(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT) < 0) {
        console.error('[FATAL] prepareService failed');
        return 1;
    }

    // 3. Create the App + register the APIs + connect to the same
    //    endpoint as a client
    let app = createAndRegisterHttpJsonApp();
    if (!app) {
        console.error('[FATAL] createAndRegisterHttpJsonApp failed');
        return 1;
    }

    if (framework.prepareClient(HTTP_SERVICE_ENDPOINT, app) < 0) {
        console.error('[FATAL] prepareClient failed');
        return 1;
    }

    if (framework.prepareDone() !== 1) {
        console.error('[FATAL] prepareDone failed');
        return 1;
    }

    console.log('[OK] Service ready. Press Ctrl+C to stop.');

    // 4. Wait for Ctrl+C
    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));
    setInterval(() => {}, 1 << 30);
    return 0;
}
```

#### 5.5.5 Filling in the business logic

**In the generated `<Unit>_http_json_service_node.js`**, find the `internal_call_<Api>` stub:

```javascript
function internal_call_Add(a, b) {
    // TODO: implement this stub.
    return 0;  // ← replace this
}
```

**Recommended practice**: create `calculator_impl.js` and let the stub do `return require('./calculator_impl').add(a, b);`.

#### 5.5.6 Shutdown

```javascript
framework.exitMainThread();
app.dispose();
framework.shutdown();
```

#### 5.5.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Cannot find module 'lingofuse-js'` | not installed | `npm install lingofuse-js` |
| `prepareService failed` | the endpoint is already taken | change the endpoint or kill the old process |
| `prepareDone failed` | already called in this process | restart the process |

---

### 5.6 TypeScript

#### 5.6.1 Artifacts

```
<Unit>_http_json_service.ts
```

#### 5.6.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| `lingofuse-ts` | npm | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| TypeScript 5.0+ | npm | ✅ |
| `tsx` | npm | ✅ (to run .ts directly) |
| Node.js 18+ | — | ✅ |

#### 5.6.3 Platform

- **Runtime**: Node.js 18+ (through `tsx`).
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.6.4 Initialization

**The generated `main()` already contains the complete flow**:

```bash
./node_modules/.bin/tsx.cmd <Unit>_http_json_service.ts
```

**The core flow of `main()`**:

```typescript
export function main(): number {
    // 1. Configure
    lf.options.setOptWaitConnectionReadyOk(false);
    lf.options.setOptOverlapConnection(true);
    lf.framework.resetPrepare();

    // 2. Listen on the endpoint
    if (lf.framework.prepareService(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT) < 0) {
        console.error(`[FATAL] prepareService failed`);
        return 1;
    }

    // 3. Create the App + register the APIs + connect to the same
    //    endpoint as a client
    let app = createAndRegisterHttpJsonApp();
    if (!app) return 1;

    if (lf.framework.prepareClient(HTTP_SERVICE_ENDPOINT, app) < 0) {
        console.error(`[FATAL] prepareClient failed`);
        return 1;
    }

    if (lf.framework.prepareDone() !== 1) {
        console.error(`[FATAL] prepareDone failed`);
        return 1;
    }

    console.log("[OK] Service ready. Press Ctrl+C to stop.");

    // 4. Wait for Ctrl+C
    process.on("SIGINT", () => shutdown("SIGINT"));
    process.on("SIGTERM", () => shutdown("SIGTERM"));
    setInterval(() => {}, 1 << 30);
    return 0;
}
```

#### 5.6.5 Filling in the business logic

**In the generated `<Unit>_http_json_service.ts`**, find the `internal_call_<Api>` stub:

```typescript
export function internal_call_Add(a: number, b: number): number {
    // TODO: implement this stub.
    return 0;  // ← replace this
}
```

**Recommended practice**: create `calculator_impl.ts` and let the stub do `return calculator_impl.add(a, b);`.

#### 5.6.6 Shutdown

```typescript
try { lf.network.clearNetworkEvent(); } catch { }
try { lf.AsyncBridge.shutdownInstance(); } catch { }
try { lf.framework.exitMainThread(); } catch { }
try { app?.dispose(); } catch { }
try { lf.framework.shutdown(); } catch { }
```

#### 5.6.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Cannot find module 'lingofuse-ts'` | not installed | `npm install lingofuse-ts` |
| `tsx: not found` | not installed | `npm install tsx` |
| `prepareService failed` | the endpoint is already taken | change the endpoint or kill the old process |

---

### 5.7 Rust

#### 5.7.1 Artifacts

```
<Unit>_http_json_service_rs.rs
```

#### 5.7.2 Dependencies

**`Cargo.toml`**:

```toml
[dependencies]
lingofuse = { path = "../LingoFuse/rust" }
serde_json = "1"
```

| Dependency | Source | Required |
|------|------|:----:|
| the `lingofuse` crate | LingoFuse distribution | ✅ |
| `serde_json` | crates.io | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| Rust 1.70+ | — | ✅ |

#### 5.7.3 Platform

- **Compiler / runtime**: Rust 1.70+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.7.4 Initialization

**The generated `run_service()` already contains the complete flow**:

```bash
cargo new my_service
cd my_service
cargo add lingofuse --path ../LingoFuse/rust
cargo add serde_json
cp ../<Unit>_http_json_service_rs.rs src/main.rs
cargo run
```

**The core flow of `run_service()`**:

```rust
pub fn run_service() -> Result<AppHandle, Box<dyn std::error::Error>> {
    println!("=== {} HTTP/JSON service ===", APP_NAME);

    // 1. Create the App
    let app = AppHandle::new(APP_NAME, APP_DESC)?;

    // 2. Register the APIs
    register_all_apis(&app)?;

    // 3. Configure
    framework::set_option("Wait_Connection_ReadyOk", "False")?;
    framework::set_option("Overlap_Connection", "True")?;
    framework::reset_prepare();

    // 4. Listen on the endpoint
    let serv_tag = framework::prepare_service(ENDPOINT, ENDPOINT)?;
    if serv_tag < 0 {
        return Err(format!("prepare_service failed: {}", serv_tag).into());
    }

    // 5. Connect to the same endpoint as a client
    let cli_tag = framework::prepare_client(ENDPOINT, Some(&app))?;
    if cli_tag < 0 {
        return Err(format!("prepare_client failed: {}", cli_tag).into());
    }

    // 6. Start the mesh
    if !framework::prepare_done()? {
        return Err("prepare_done returned false".into());
    }

    println!("[OK] Service ready. Press Ctrl+C to stop.");
    Ok(app)
}

fn main() {
    let _app = match run_service() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("[FATAL] {}", e);
            std::process::exit(1);
        }
    };

    loop {
        std::thread::sleep(Duration::from_millis(500));
    }
}
```

#### 5.7.5 Filling in the business logic

**In the generated `<Unit>_http_json_service_rs.rs`**, find the `internal_call_<Api>` stub:

```rust
pub fn internal_call_Add(a: i64, b: i64) -> i64 {
    let _ = (a, b);
    // TODO: replace this body with the real implementation.
    0  // ← replace this
}
```

**Recommended practice**: create `calculator_impl.rs` and let the stub do `calculator_impl::add(a, b)`.

#### 5.7.6 Shutdown

```rust
// the App's Drop frees the app automatically
// unloading the LingoFuse native library is handled by the lingofuse crate's Drop
```

#### 5.7.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `lingofuse not found` | `cargo add` was not run | `cargo add lingofuse --path ../LingoFuse/rust` |
| `linking with cc failed` | no C linker | install MSVC Build Tools or gcc |
| `prepare_service failed` | the endpoint is already taken | change the endpoint or kill the old process |

---

### 5.8 Go

#### 5.8.1 Artifacts

```
<Unit>_http_json_service_go.go
```

#### 5.8.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| `github.com/PassByYou888/LingoFuse/go` | GitHub | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| Go 1.21+ | — | ✅ |
| `CGO_ENABLED=1` | — | ✅ (the service side needs cgo) |

#### 5.8.3 Platform

- **Runtime**: Go 1.21+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64). **Mobile / WASM are unavailable because cgo is required.**

#### 5.8.4 Initialization

**The generated `runService()` already contains the complete flow**:

```bash
go mod init my_service
go get github.com/PassByYou888/LingoFuse/go
cp ../<Unit>_http_json_service_go.go .
cp ../<Unit>_http_json_service_main_test.go .
CGO_ENABLED=1 go test -v
```

**The core flow of `runService()`**:

```go
func runService() error {
    fmt.Println("=== " + AppName + " HTTP/JSON service ===")

    // 1. Create the App
    app, err := lingofuse.NewAppHandle(AppName, AppDesc)
    if err != nil {
        return fmt.Errorf("create app: %w", err)
    }
    defer func() {
        _ = lingofuse.ExitMainThread()
        app.Close()
        _ = lingofuse.Shutdown()
    }()

    // 2. Register the APIs
    if err := registerAllAPIs(app); err != nil {
        return err
    }

    // 3. Configure
    if err := lingofuse.SetOption("Wait_Connection_ReadyOk", "False"); err != nil {
        return err
    }
    if err := lingofuse.SetOption("Overlap_Connection", "True"); err != nil {
        return err
    }
    if err := lingofuse.ResetPrepare(); err != nil {
        return err
    }

    // 4. Listen on the endpoint
    if _, err := lingofuse.PrepareService(Endpoint, Endpoint); err != nil {
        return fmt.Errorf("PrepareService: %w", err)
    }

    // 5. Connect to the same endpoint as a client
    if _, err := lingofuse.PrepareClient(Endpoint, app); err != nil {
        return fmt.Errorf("PrepareClient: %w", err)
    }

    // 6. Start the mesh
    started, err := lingofuse.PrepareDone()
    if err != nil {
        return fmt.Errorf("PrepareDone: %w", err)
    }
    if !started {
        return fmt.Errorf("PrepareDone returned false")
    }

    fmt.Println("[OK] Service ready. Press Ctrl+C to stop.")

    // 7. Wait for a signal
    sigCh := make(chan os.Signal, 1)
    signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
    <-sigCh
    return nil
}
```

#### 5.8.5 Filling in the business logic

**In the generated `<Unit>_http_json_service_go.go`**, find the `internalCall<Api>` stub:

```go
func internalCallAdd(a int64, b int64) (int64, error) {
    _ = a
    _ = b
    // TODO: replace this body with the real implementation.
    return 0, nil  // ← replace this
}
```

**Recommended practice**: create `calculator_impl.go` and let the stub do `return calculator_impl.Add(a, b)`.

#### 5.8.6 Shutdown

```go
defer func() {
    _ = lingofuse.ExitMainThread()
    app.Close()
    _ = lingofuse.Shutdown()
}()
```

#### 5.8.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `module github.com/PassByYou888/LingoFuse not found` | `go get` was not run | `go get github.com/PassByYou888/LingoFuse/go` |
| cgo-related errors | `CGO_ENABLED=0` | `CGO_ENABLED=1 go build` |
| `PrepareService failed` | the endpoint is already taken | change the endpoint or kill the old process |

---

### 5.9 Java

#### 5.9.1 Artifacts

```
HttpJsonService.java
```

#### 5.9.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| the `lingofuse` Java package | LingoFuse distribution | ✅ |
| `jackson-databind.jar` | Maven Central | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| JDK 11+ | — | ✅ |

#### 5.9.3 Platform

- **Runtime**: JDK 11+ (17+ recommended).
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.9.4 Initialization

**The generated `main()` already contains the complete flow**:

```bash
javac -cp lingofuse.jar:jackson-databind.jar *.java
java --enable-native-access=ALL-UNNAMED \
     -cp .:lingofuse.jar:jackson-databind.jar \
     HttpJsonService
```

**The core flow of `main()`**:

```java
public static void main(String[] args) {
    System.out.println("=== " + HTTP_SERVICE_APP_NAME + " HTTP/JSON service ===");
    System.out.println("Endpoint: " + HTTP_SERVICE_ENDPOINT);

    AppHandle app = null;
    boolean started = false;

    try {
        // 1. Configure
        Framework.setOption("Wait_Connection_ReadyOk", "False");
        Framework.setOption("Overlap_Connection", "True");
        Framework.resetPrepare();

        // 2. Create the App + register the APIs
        app = createAndRegister();

        // 3. Listen on the endpoint
        int servRet = Framework.prepareService(
            HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT);
        if (servRet < 0) {
            System.err.println("[FATAL] prepareService failed");
            throw new RuntimeException("prepareService failed");
        }

        // 4. Connect to the same endpoint as a client
        int clientRet = Framework.prepareClient(HTTP_SERVICE_ENDPOINT, app);
        if (clientRet < 0) {
            System.err.println("[FATAL] prepareClient failed");
            throw new RuntimeException("prepareClient failed");
        }

        // 5. Start the mesh
        int doneRet = Framework.prepareDone();
        if (doneRet != 1 && !LingoFuseStatus.checkMainThread()) {
            System.err.println("[FATAL] prepareDone failed");
            throw new RuntimeException("prepareDone failed");
        }
        started = true;

        System.out.println("[OK] Service ready. Press Ctrl+C to stop.");

        // 6. Wait for Ctrl+C
        final AppHandle appFinal = app;
        final boolean startedFinal = started;
        Runtime.getRuntime().addShutdownHook(new Thread(
            () -> cleanupOnce(appFinal, startedFinal), "lf-shutdown"));

        try {
            Thread.sleep(Long.MAX_VALUE);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    } catch (Throwable t) {
        System.err.println("[FATAL] " + t.getClass().getSimpleName() + ": " + t.getMessage());
        cleanupOnce(app, started);
        System.exit(1);
    }
}
```

#### 5.9.5 Filling in the business logic

**In the generated `HttpJsonService.java`**, find the `internalCall_<Api>` stub:

```java
private static long internalCall_Add(long a, long b) {
    // TODO: implement this stub.
    // Suggested call: Add(a, b)
    return 0L;  // ← replace this
}
```

**Recommended practice**: create `CalculatorImpl.java` and let the stub do `return CalculatorImpl.Add(a, b);`.

#### 5.9.6 Shutdown

```java
private static void cleanupOnce(AppHandle app, boolean started) {
    try { NetworkEvents.clear(); } catch (Throwable ignored) { }
    if (started) {
        try { Framework.exitMainThread(); } catch (Throwable ignored) { }
    }
    if (app != null) {
        try { app.close(); } catch (Throwable ignored) { }
    }
    if (started) {
        try { Framework.shutdown(); } catch (Throwable ignored) { }
    }
}
```

#### 5.9.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `UnsatisfiedLinkError: LingoFuse64` | the native library is missing | add it to `-Djava.library.path` |
| `ClassNotFoundException: lingofuse.AppHandle` | `lingofuse.jar` is missing | install the LingoFuse Java package |
| `ClassNotFoundException: jackson.databind.JsonNode` | Jackson is missing | download `jackson-databind.jar` |
| `prepareService failed` | the endpoint is already taken | change the endpoint or kill the old process |

---

### 5.10 Dart

#### 5.10.1 Artifacts

```
<Unit>_http_json_service.dart
```

#### 5.10.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| the `lingofuse` Dart package | LingoFuse distribution | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| Dart 3.0+ | — | ✅ |

#### 5.10.3 Platform

- **Runtime**: Dart 3.0+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64). **Mobile is unavailable because the LingoFuse native library is required.**

#### 5.10.4 Initialization

**The generated `main()` already contains the complete flow**:

```bash
dart run <Unit>_http_json_service.dart
```

**The core flow of `main()`**:

```dart
Future<void> main(List<String> args) async {
    print('=== $HTTP_SERVICE_APP_NAME HTTP/JSON service ===');
    print('Endpoint: $HTTP_SERVICE_ENDPOINT');

    // 1. Start the C bridge (Dart-specific: BridgeHost)
    await BridgeHost.start();

    // 2. Create the App + register the APIs
    final app = AppHandle(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC);
    register_all_http_json_apis(app);

    // 3. Configure
    Framework.setOption('Quiet', 'True');
    Framework.setOption('Wait_Connection_ReadyOk', 'False');
    Framework.setOption('Overlap_Connection', 'True');
    Framework.resetPrepare();

    // 4. Listen on the endpoint + connect to the same endpoint as a client
    Framework.prepareService(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT);
    Framework.prepareClient(HTTP_SERVICE_ENDPOINT, app: app);

    // 5. Start the mesh
    if (!Framework.prepareDone()) {
        stderr.writeln('[FATAL] prepareDone failed');
        await _shutdown(app);
        exit(1);
    }

    // 6. Wait for the mesh to see it
    bool visible = false;
    for (int i = 0; i < 30; i++) {
        if (Framework.checkApp(HTTP_SERVICE_APP_NAME)) {
            visible = true;
            break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
    }

    print('[OK] Service ready. Press Ctrl+C to stop.');

    // 7. Wait for Ctrl+C
    await _waitForShutdown();

    // 8. Shutdown
    await _shutdown(app);
}
```

#### 5.10.5 Filling in the business logic

**In the generated `<Unit>_http_json_service.dart`**, find the `internal_call_<Api>` stub:

```dart
int internal_call_Add(int a, int b) {
    // TODO: implement this stub.
    return 0;  // ← replace this
}
```

**Recommended practice**: create `calculator_impl.dart` and let the stub do `return calculator_impl.add(a, b);`.

#### 5.10.6 Shutdown

```dart
Future<void> _shutdown(AppHandle app) async {
    try { app.dispose(); } catch (_) {}
    try { Framework.exitMainThread(); } catch (_) {}
    try { Framework.shutdown(); } catch (_) {}
    try { BridgeHost.instance.stop(); } catch (_) {}
}
```

#### 5.10.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Error: Couldn't resolve the package 'lingofuse'` | `dart pub get` was not run | `dart pub get` |
| `prepareDone returned false` | `Wait_Connection_ReadyOk` was not disabled | set it to `False` |
| `prepareService failed` | the endpoint is already taken | change the endpoint or kill the old process |

---

### 5.11 Swift

#### 5.11.1 Artifacts

```
<Unit>_http_json_service_swift.swift
```

#### 5.11.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| the `lingofuse` Swift binding | LingoFuse distribution | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| Swift 5.9+ | — | ✅ |

#### 5.11.3 Platform

- **Compiler / runtime**: Swift 5.9+.
- **OS**: macOS 12+, Linux. **iOS is unavailable because the LingoFuse native library is required.**

#### 5.11.4 Initialization

**The generated `runService()` already contains the complete flow**:

```bash
swift <Unit>_http_json_service.swift
```

**The core flow of `runService()`**:

```swift
public static func runService() throws -> AppHandle {
    // 1. Load the LingoFuse native library
    guard LF_LoadLibrary() == 1 else {
        throw ServiceError.libraryLoadFailed
    }

    // 2. Configure
    Framework.setOption("Wait_Connection_ReadyOk", "False")
    Framework.setOption("Overlap_Connection", "True")
    Framework.setOption("Quiet", debugLog ? "False" : "True")
    Framework.resetPrepare()

    // 3. Listen on the endpoint
    do {
        _ = try Framework.prepareService(
            listeningAddr: endpoint,
            physicsAddr: endpoint)
    } catch {
        throw ServiceError.prepareServiceFailed("\(error)")
    }

    // 4. Create the App + register the APIs
    let app = try AppHandle(name: appName, description: appDescription)
    try registerAllApis(app)

    // 5. Connect to the same endpoint as a client
    do {
        _ = try Framework.prepareClient(physicsAddr: endpoint, app: app)
    } catch {
        app.dispose()
        throw ServiceError.prepareClientFailed("\(error)")
    }

    // 6. Start the mesh
    if !Framework.prepareDone() && !Framework.checkMainThread() {
        app.dispose()
        throw ServiceError.prepareDoneFailed
    }

    return app
}
```

#### 5.11.5 Filling in the business logic

**In the generated `<Unit>_http_json_service_swift.swift`**, find the `internal_call_<Api>` stub:

```swift
public static func internal_call_Add(_ a: Int64, _ b: Int64) -> Int64 {
    _ = (a, b)
    // TODO: replace this body with the real implementation.
    return 0  // ← replace this
}
```

**Recommended practice**: create `CalculatorImpl.swift` and let the stub do `return CalculatorImpl.add(a, b)`.

#### 5.11.6 Shutdown

```swift
NetworkEvents.clearNetworkEvent()
Framework.exitMainThread()
app.dispose()
Framework.shutdown()
LF_FreeLibrary()
```

#### 5.11.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `libraryLoadFailed` | `LingoFuse64.dylib` is missing | copy it next to the executable |
| `prepareServiceFailed` | the endpoint is already taken | change the endpoint or kill the old process |
| `prepareDoneFailed` | already called in this process | restart the process |

---

### 5.12 Ruby

#### 5.12.1 Artifacts

```
<Unit>_http_json_service.rb
<Unit>_http_json_service_impl.rb (where applicable)
```

#### 5.12.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| the `lingofuse` gem | RubyGems / LingoFuse distribution | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| Ruby 2.7+ / 3.0+ | — | ✅ |

#### 5.12.3 Platform

- **Runtime**: Ruby 2.7+ / 3.0+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.12.4 Initialization

**The generated `main()` already contains the complete flow**:

```bash
gem install lingofuse  # only needed once
ruby <Unit>_http_json_service.rb
```

**The core flow of `main()`**:

```ruby
def self.main
    $stdout.puts "=== #{APP_NAME} HTTP/JSON service ==="
    $stdout.puts "Endpoint: #{ENDPOINT}"

    begin
        LingoFuse.set_opt_wait_connection_ready_ok(false)
        LingoFuse.set_opt_overlap_connection(true)
    rescue StandardError
    end

    LingoFuse::Framework.reset_prepare

    # 1. Listen on the endpoint
    begin
        LingoFuse::Framework.prepare_service(ENDPOINT, ENDPOINT)
    rescue StandardError => e
        warn "[FATAL] prepare_service failed: #{e.message}"
        return 1
    end

    # 2. Create the App + register the APIs
    app = begin
        create_and_register_http_json_app
    rescue StandardError => e
        warn "[FATAL] create_and_register failed: #{e.message}"
        return 1
    end
    return 1 if app.nil?

    # 3. Connect to the same endpoint as a client
    begin
        LingoFuse::Framework.prepare_client(ENDPOINT, app)
    rescue StandardError => e
        warn "[FATAL] prepare_client failed: #{e.message}"
        app.dispose rescue nil
        return 1
    end

    # 4. Start the mesh
    unless LingoFuse::Framework.prepare_done
        warn "[FATAL] prepare_done failed"
        app.dispose rescue nil
        return 1
    end

    $stdout.puts '[OK] Service ready. Press Ctrl+C to stop.'

    # 5. Wait for Ctrl+C
    stop = false
    prev_int = trap('INT') { stop = true }
    begin
        until stop
            sleep(0.5)
        end
    rescue Interrupt
        stop = true
    end

    # 6. Shutdown
    LingoFuse::Framework.exit_main_thread rescue nil
    app.dispose rescue nil
    LingoFuse::Framework.shutdown rescue nil
    $stdout.puts 'Service stopped.'
    0
end
```

#### 5.12.5 Filling in the business logic

**In the generated `<Unit>_http_json_service.rb`**, find the `internal_call_<Api>` stub:

```ruby
def self.internal_call_add(a, b)
    # TODO: replace this body with the real implementation.
    0  # ← replace this
end
```

**Recommended practice**: create `calculator_impl.rb` and let the stub do `CalculatorImpl.add(a, b)`.

#### 5.12.6 Shutdown

```ruby
LingoFuse::Framework.exit_main_thread rescue nil
app.dispose rescue nil
LingoFuse::Framework.shutdown rescue nil
```

#### 5.12.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `cannot load such file -- lingofuse` | the gem is not installed | `gem install lingofuse` |
| `prepare_service failed` | the endpoint is already taken | change the endpoint or kill the old process |
| the process does not exit | the `NativeBridge` thread was not joined | the generated code already forces exit with `exit!` |

---

### 5.13 Zig

#### 5.13.1 Artifacts

```
<Unit>_http_json_service_zig.zig
```

#### 5.13.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| the `lingofuse` Zig binding (`src/lingofuse.zig`) | LingoFuse distribution | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| Zig 0.13+ | — | ✅ |

#### 5.13.3 Platform

- **Compiler**: Zig 0.13+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.13.4 Initialization

**The generated `runService()` already contains the complete flow**:

```bash
cd zig_service_test
zig build run
```

**The core flow of `runService()`**:

```zig
pub fn runService() !void {
    // 1. Load LingoFuse
    try lf.framework.init();
    errdefer lf.framework.deinit();

    // 2. Configure
    lf.options.setWaitConnectionReadyOk(false) catch {};
    lf.options.setOverlapConnection(true) catch {};
    lf.options.setQuiet(true) catch {};
    lf.framework.resetPrepare();

    // 3. Create the App + register the APIs
    var app = try lf.AppHandle.create(APP_NAME, APP_DESC);
    errdefer app.deinit();
    try registerAllApis(&app);

    // 4. Listen on the endpoint + connect to the same endpoint as a client
    _ = try lf.framework.prepareService(ENDPOINT, ENDPOINT);
    _ = try lf.framework.prepareClient(ENDPOINT, &app);

    // 5. Start the mesh
    _ = lf.framework.prepareDone();

    std.debug.print("[service] Online on endpoint {s}\n", .{ENDPOINT});
    std.debug.print("[service] Press Enter to stop.\n", .{});
    _ = getchar();

    // 6. Shutdown
    lf.framework.exitMainThread();
    app.deinit();
    lf.framework.shutdown();
}
```

#### 5.13.5 Filling in the business logic

**In the generated `<Unit>_http_json_service_zig.zig`**, find the `internal_call_<Api>` stub:

```zig
pub fn internal_call_Add(a: i64, b: i64) i64 {
    _ = a;
    _ = b;
    // TODO: implement this stub.
    return 0;  // ← replace this
}
```

**Recommended practice**: create `calculator_impl.zig` and let the stub do `return calculator_impl.add(a, b)`.

#### 5.13.6 Shutdown

```zig
lf.framework.exitMainThread();
app.deinit();
lf.framework.shutdown();
```

#### 5.13.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `framework.init failed` | `LingoFuse64.dll` is missing | copy it into `zig_service_test/` |
| `prepareService failed` | the endpoint is already taken | change the endpoint or kill the old process |
| `std.array_list.Managed` compile error | the Zig version is too old | use Zig 0.13+ |

---

### 5.14 Erlang

#### 5.14.1 Artifacts

```
<Unit>_http_json_service.erl
```

#### 5.14.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| the `lingofuse` Erlang binding | LingoFuse distribution | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| Erlang/OTP 25+ | — | ✅ |

#### 5.14.3 Platform

- **Runtime**: Erlang/OTP 25+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.14.4 Initialization

**The generated `main/0` already contains the complete flow**:

```bash
escript <Unit>_http_json_service_main_test___.escript
```

**The core flow of `main/0`**:

```erlang
main() ->
    ok = ensure_native(),
    AppName = app_name(),
    AppDesc = app_desc(),
    Endpoint = bridge_endpoint(),

    % 1. Create the App
    {ok, App} = lingofuse:create_app(AppName, AppDesc),

    % 2. Configure
    ok = set_deployment_mode(),
    ok = do_reset_prepare(),

    % 3. Listen on the endpoint
    ok = do_prepare_service(Endpoint),

    % 4. Register the APIs
    ok = register_all_apis(App, self()),

    % 5. Connect to the same endpoint as a client
    ok = do_prepare_client(Endpoint, App),

    % 6. Start the mesh
    ok = do_prepare_done(),

    % 7. Wait for the App to become visible
    ok = wait_self_registered(AppName, 15000),

    io:format("[OK] Service ready.~n"),
    loop(App).

loop(App) ->
    receive
        {lf_call, Ref, Api, Payload} when is_integer(Ref) ->
            _ = spawn(fun() -> handle_request(Api, Ref, Payload) end),
            loop(App);
        stop ->
            cleanup(App),
            ok;
        _Other ->
            loop(App)
    end.
```

#### 5.14.5 Filling in the business logic

**In the generated `<Unit>_http_json_service.erl`**, find the `internal_call_<Api>` stub:

```erlang
%% HTTP/JSON API: Add.
internal_call_add(A, B) ->
    %% Suggested call: add(A, B).
    0.  %% ← replace this
```

**Recommended practice**: create `calculator_impl.erl` and let the stub call `calculator_impl:add(A, B)`.

#### 5.14.6 Shutdown

```erlang
cleanup(App) ->
    try lingofuse:exit_main_thread() catch _:_ -> ok end,
    try lingofuse:free_app(App)       catch _:_ -> ok end,
    try lingofuse:shutdown()           catch _:_ -> ok end,
    ok.
```

#### 5.14.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `no such file or directory: lingofuse_nif.dll` | the NIF is missing | `setup_erlang_tests.ps1` copies it |
| `prepare_service_failed` | the endpoint is already taken | change the endpoint or kill the old process |
| `app_not_registered` | the App was not visible within 15 seconds | check the `wait_self_registered` timeout |

---

### 5.15 Fortran

#### 5.15.1 Artifacts

```
<Unit>_http_json_service_mod.f90
```

#### 5.15.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| `lf_fortran_mod.f90` | LingoFuse distribution | ✅ |
| `lf_fortran.cpp` | LingoFuse distribution | ✅ |
| `LingoFuse.c` | LingoFuse distribution | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| gfortran 9+ | — | ✅ |

#### 5.15.3 Platform

- **Compiler**: gfortran 9+ / ifort / flang.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.15.4 Initialization

**The generated `service_test.exe` already contains the complete flow** (built by `setup_fortran_tests.ps1`):

```bash
cd _build_fortran
./service_test.exe
```

**The core flow of `service_test.exe`**:

```fortran
program service_main_test
  use iso_c_binding
  use lf_fortran_mod
  use <Unit>_http_json_service_mod
  implicit none

  type(c_ptr) :: app
  integer(c_int) :: rc, reg_rc

  ! 1. Configure
  call lf_reset_prepare()
  call lf_set_opt_wait_ready_ok(.false.)
  call lf_set_opt_overlap_connection(.true.)

  ! 2. Listen on the endpoint
  rc = lf_prepare_service('ipc:<Unit>_http_json', 'ipc:<Unit>_http_json')
  if (rc < 0) then
    write(*, '(A)') '[FATAL] lf_prepare_service failed'
    stop 1
  end if

  ! 3. Create the App + register the APIs
  app = lf_app_create(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC)
  call register_all_http_json_apis(app, reg_rc)

  ! 4. Connect to the same endpoint as a client
  rc = lf_prepare_client('ipc:<Unit>_http_json', app)
  if (rc < 0) then
    stop 1
  end if

  ! 5. Start the mesh
  if (lf_prepare_done() /= 1_c_int) then
    stop 1
  end if

  write(*, '(A)') '[OK] Service ready. Press Enter to stop.'
  read (*, *)

  ! 6. Shutdown
  call lf_exit_main_thread()
  call lf_app_destroy(app)
  call lf_shutdown()
end program
```

#### 5.15.5 Filling in the business logic

**In the generated `<Unit>_http_json_service_mod.f90`**, find the `internal_call_<Api>` function:

```fortran
function internal_call_add(a, b) result(res)
  integer(c_int64_t), intent(in) :: a, b
  integer(c_int64_t) :: res

  ! TODO: replace the body below with a call to the real implementation.
  ! Example: res = add(a, b)
  res = 0_c_int64_t  ! ← replace this
end function
```

**Recommended practice**: create `calculator_impl.f90`, `use calculator_impl`, and `res = calculator_impl_add(a, b)`.

#### 5.15.6 Shutdown

```fortran
call lf_exit_main_thread()
call lf_app_destroy(app)
call lf_shutdown()
```

#### 5.15.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `gfortran: command not found` | not installed | `apt install gfortran` or MinGW-w64 |
| `lf_prepare_service failed` | the endpoint is already taken | change the endpoint or kill the old process |
| `LF_PrepareDone` returns something other than 1 | already called in this process | restart the process |

---

### 5.16 Julia

#### 5.16.1 Artifacts

```
<Unit>_http_json_service.jl
```

#### 5.16.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| the `LingoFuse` Julia binding | LingoFuse distribution | ✅ |
| `JSON3` | Julia registry | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| Julia 1.9+ | — | ✅ |
| **`--threads=2` or more** | — | ✅ |

#### 5.16.3 Platform

- **Runtime**: Julia 1.9+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64). **Mobile is unavailable because the LingoFuse native library is required.**

#### 5.16.4 Initialization

**The generated `run_service()` already contains the complete flow**:

```bash
julia --threads=2 <Unit>_http_json_service.jl
```

**The core flow of `run_service()`**:

```julia
function run_service()::Int32
    # 1. Configure
    set_option("Wait_Connection_ReadyOk", "False")
    reset_prepare()

    # 2. Listen on the endpoint
    serv_ret = prepare_service(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT)
    if serv_ret == -1
        println(stderr, "[ERROR] prepare_service failed")
        return Int32(1)
    end

    # 3. Create the App + register the APIs
    app = App(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC)
    try
        register_all_http_json_apis(app)

        # 4. Connect to the same endpoint as a client
        client_ret = prepare_client(HTTP_SERVICE_ENDPOINT, app)
        if client_ret == -1
            println(stderr, "[ERROR] prepare_client failed")
            return Int32(1)
        end

        # 5. Start the mesh
        if prepare_done() != 1
            println(stderr, "[ERROR] prepare_done failed")
            return Int32(1)
        end

        println("[OK] Service ready. Press Ctrl+C to stop.")
        Base.exit_on_sigint(false)
        try
            _wait_for_signal()
        finally
            Base.exit_on_sigint(true)
        end

        # 6. Shutdown
        exit_main_thread()
        println("[OK] Service stopped.")
    finally
        dispose!(app)
        shutdown()
    end
    return Int32(0)
end
```

#### 5.16.5 Filling in the business logic

**In the generated `<Unit>_http_json_service.jl`**, find the `internal_call_<Api>` stub:

```julia
function internal_call_Add(a::Int64, b::Int64)::Int64
    # TODO: implement this stub.
    # Suggested call: Add(a, b)
    return Int64(0)  # ← replace this
end
```

**Recommended practice**: create `calculator_impl.jl` and let the stub do `return calculator_impl.add(a, b)`.

#### 5.16.6 Shutdown

```julia
exit_main_thread()
dispose!(app)
shutdown()
```

#### 5.16.7 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `--threads=2 or more required` | single-threaded | add `--threads=2` |
| `prepare_client returned -1` | the endpoint is already taken | change the endpoint or kill the old process |
| `prepare_done failed` | already called in this process | restart the process |

---

### 5.17 R

#### 5.17.1 Artifacts

```
<Unit>_http_json_service.R
<Unit>_http_json_service_impl.R
```

#### 5.17.2 Dependencies

| Dependency | Source | Required |
|------|------|:----:|
| the `lingofuse` R package | LingoFuse distribution | ✅ |
| `jsonlite` | CRAN | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse distribution | ✅ (runtime) |
| `z_ipc_64.dll` | LingoFuse distribution | ✅ (runtime) |
| R 4.0+ | — | ✅ |

#### 5.17.3 Platform

- **Runtime**: R 4.0+.
- **OS**: Windows (x64), Linux (x64/arm64), macOS (x64/arm64).

#### 5.17.4 Initialization

**The generated `.R` script already contains the complete flow**:

```bash
Rscript <Unit>_http_json_service.R
```

**The core flow of `_main`**:

```r
.main <- function() {
    cat("=== ", APP_NAME, " native R LingoFuse service ===\n", sep = "")

    # 1. Load the user implementation
    .load_impl()

    # 2. Load the LingoFuse native library
    rt <- .resolve_runtime_dir()
    lingofuse::lf_load(runtime_dir = rt)

    # 3. Create the App
    app <- lingofuse::lf_create_app(APP_NAME, APP_DESC)

    # 4. Register the APIs
    for (spec in api_specs) {
        cb <- .make_cb(spec$name, spec$params, spec$description)
        ok <- lingofuse::lf_register_call(app, spec$name, spec$description, cb)
    }

    # 5. Listen on the endpoint + connect to the same endpoint as a client
    svc_tag <- lingofuse::lf_prepare_service(LF_ENDPOINT, LF_ENDPOINT)
    cli_tag <- lingofuse::lf_prepare_client(LF_ENDPOINT, app)
    rc <- lingofuse::lf_prepare_done()

    # 6. Wait for the service.exit sentinel file
    running <- TRUE
    while (running) {
        result <- tryCatch({
            lingofuse::lf_poll(100)
            "ok"
        }, ...)

        if (file.exists(sentinel)) {
            file.remove(sentinel)
            running <- FALSE
        }
    }

    # 7. Shutdown
    lingofuse::lf_exit_main_thread()
    lingofuse::lf_free_app(app)
    lingofuse::lf_shutdown()
    quit(save = "no", status = 0)
}
```

#### 5.17.5 Filling in the business logic

**In the generated `<Unit>_http_json_service_impl.R`**, find each `internal_call_<api>` function:

```r
add <- function(a, b) {
    # TODO: implement.
    return(0)  # ← replace this
}
```

**Recommended practice**: put the business logic in a separate `.R` file, `source()` it in, and let `impl.R` only forward.

#### 5.17.6 Shutdown

```r
lingofuse::lf_exit_main_thread()
lingofuse::lf_free_app(app)
lingofuse::lf_shutdown()
quit(save = "no", status = 0)
```

#### 5.17.7 The recommended way to stop an R service

**Do not use Ctrl+C.** Use a separate PowerShell window to write the sentinel file:

```powershell
'' > "<script directory>\service.exit"
```

The service detects it within about 100 ms, runs `exit_main_thread` → `free_app` → `shutdown` in order, and exits.

#### 5.17.8 Common problems

| Symptom | Cause | Fix |
|------|------|------|
| `Package 'lingofuse' is required` | not installed | `setup_r_tests.ps1 -InstallMissing` |
| `Cannot locate the LingoFuse runtime` | `LINGOFUSE_RUNTIME` is not set | set the environment variable |
| `lf_prepare_service failed` | the endpoint is already taken | change the endpoint or kill the old process |

---

## 6. Languages with no service side

The following three languages **have no service side** and can only be Call:

| Language | Reason | Alternative |
|------|------|----------|
| **JavaScript (browser)** | a browser cannot load the LingoFuse native library | use Node.js / TypeScript for the Service |
| **PHP** | PHP has no LingoFuse native library support | use Python / Ruby / Java for the Service |
| **Delphi** | Delphi's `System.Net.HttpClient` is a pure HTTP client | use Pascal (FPC) for the Service |

**That means**: if you need to "expose an interface" from one of those three languages, the Service must be deployed in another language (Python / Pascal / C++ / ...) and the three languages act as a Call through the bridge.

**Architecture example**:

```
browser JS (Call) ──HTTP──▶ bridge.py ──LF_Call──▶ Python Service
```

**Not**:

```
browser JS (Service)  ← impossible
```

---

## 7. Platform and OS support matrix

### 7.1 By language

| Language | Compiler / runtime | Windows | Linux | macOS | Other OS |
|------|----------------|:-------:|:-----:|:-----:|---------|
| Pascal | FPC 3.2+ / Delphi 11+ | ✅ | ✅ | ✅ | limited by the LingoFuse native library |
| Python | Python 3.8+ | ✅ | ✅ | ✅ | limited by the LingoFuse Python package |
| C++ | C++17 compiler | ✅ | ✅ | ✅ | limited by the LingoFuse native library |
| C# | .NET 8.0+ | ✅ | ✅ | ✅ | limited by the LingoFuse .NET binding |
| Node.js | Node.js 18+ | ✅ | ✅ | ✅ | limited by the LingoFuse native library |
| TypeScript | Node.js 18+ | ✅ | ✅ | ✅ | limited by the LingoFuse native library |
| Rust | Rust 1.70+ | ✅ | ✅ | ✅ | limited by the LingoFuse native library |
| Go | Go 1.21+ + cgo | ✅ | ✅ | ✅ | limited by the LingoFuse native library |
| Java | JDK 11+ | ✅ | ✅ | ✅ | limited by the LingoFuse Java package |
| Dart | Dart 3.0+ | ✅ | ✅ | ✅ | limited by the LingoFuse Dart package |
| Swift | Swift 5.9+ | ✅ | ✅ | ✅ | limited by the LingoFuse Swift binding |
| Ruby | Ruby 2.7+ / 3.0+ | ✅ | ✅ | ✅ | limited by the LingoFuse gem |
| Zig | Zig 0.13+ | ✅ | ✅ | ✅ | limited by the LingoFuse native library |
| Erlang | Erlang/OTP 25+ | ✅ | ✅ | ✅ | limited by the LingoFuse Erlang binding |
| Fortran | gfortran 9+ | ✅ | ✅ | ✅ | limited by `lf_fortran.cpp` |
| Julia | Julia 1.9+ | ✅ | ✅ | ✅ | limited by the LingoFuse Julia binding |
| R | R 4.0+ | ✅ | ✅ | ✅ | limited by the `lingofuse` R package |

### 7.2 By OS

| OS | Service support | Notes |
|----------|:------------:|------|
| **Windows (x86 / x64 / arm64)** | ✅ all 17 languages | needs `LingoFuse64.dll` + `z_ipc_64.dll` |
| **Linux (x64 / arm64)** | ✅ all 17 languages | needs `liblingofuse.so` + `libz_ipc_64.so` |
| **macOS (x64 / arm64)** | ✅ all 17 languages | needs `liblingofuse.dylib` |
| **iOS / iPadOS** | ❌ | not supported by the LingoFuse native library |
| **Android** | ❌ | not supported by the LingoFuse native library |
| **WASM** | ❌ | not supported by the LingoFuse native library |
| **FreeBSD / OpenBSD / NetBSD** | ❌ | not supported by the LingoFuse native library |
| **Embedded (ARM Cortex-M etc.)** | ❌ | not supported by the LingoFuse native library |

**Key conclusion**: **the Service can only be deployed on desktop / server platforms**. Mobile / embedded / WASM cannot run a Service. If you need to expose an interface to a mobile client, **deploy the Service on a server and let the mobile client act as a Call through the bridge**.

### 7.3 Comparison with the Call side's platforms

| Language | Service platform | Call platform |
|------|:------------:|:---------:|
| Python | desktop / server | every platform Python supports (including mobile) |
| JavaScript | ❌ no Service | every modern browser |
| Node.js | desktop / server | every platform Node.js supports |
| TypeScript | desktop / server | same as Node.js / browser |
| Rust | desktop / server | every platform Rust supports (including WASM, embedded) |
| Go | desktop / server (needs cgo) | every platform Go supports (including WASM, mobile) |
| Swift | desktop / server (macOS / Linux) | every platform Swift supports (including iOS) |
| Dart | desktop / server | every platform Dart supports (including mobile, Web) |
| ... | ... | ... |

**The core difference**: **the Service needs the LingoFuse native library, so its platform support is narrower; Call mode A does not need the native library, so its platform support is wider**.

---

## 8. Cross-comparison quick reference

### 8.1 Integration approach

| Language | Needs the LingoFuse native library | Needs a LingoFuse language binding | Three-piece initialization | Stub name |
|------|:--------------------:|:----------------------:|:------------:|------|
| Pascal | ✅ | ✅ | `LF_PrepareServiceEx` → `LF_PrepareClientEx` → `LF_PrepareDone` | `internal_call_<Api>` |
| Python | ✅ | ✅ | `LF_PrepareService` → `LF_PrepareClient` → `LF_PrepareDone` | `internal_call_<Api>` |
| C++ | ✅ | ✅ | `prepareService` → `prepareClient` → `prepareDone` | `internal_call_<Api>` |
| C# | ✅ | ✅ | `Framework.PrepareService` → `Framework.PrepareClient` → `Framework.PrepareDone` | `InternalCalls.<Api>` |
| Node.js | ✅ | ✅ | `framework.prepareService` → `framework.prepareClient` → `framework.prepareDone` | `internal_call_<Api>` |
| TypeScript | ✅ | ✅ | `lf.framework.prepareService` → `lf.framework.prepareClient` → `lf.framework.prepareDone` | `internal_call_<Api>` |
| Rust | ✅ | ✅ | `framework::prepare_service` → `framework::prepare_client` → `framework::prepare_done` | `internal_call_<Api>` |
| Go | ✅ | ✅ | `lingofuse.PrepareService` → `lingofuse.PrepareClient` → `lingofuse.PrepareDone` | `internalCall<Api>` |
| Java | ✅ | ✅ | `Framework.prepareService` → `Framework.prepareClient` → `Framework.prepareDone` | `internalCall_<Api>` |
| Dart | ✅ | ✅ | `Framework.prepareService` → `Framework.prepareClient` → `Framework.prepareDone` | `internal_call_<Api>` |
| Swift | ✅ | ✅ | `Framework.prepareService` → `Framework.prepareClient` → `Framework.prepareDone` | `internal_call_<Api>` |
| Ruby | ✅ | ✅ | `Framework.prepare_service` → `Framework.prepare_client` → `Framework.prepare_done` | `internal_call_<Api>` |
| Zig | ✅ | ✅ | `lf.framework.prepareService` → `lf.framework.prepareClient` → `lf.framework.prepareDone` | `internal_call_<Api>` |
| Erlang | ✅ | ✅ | `lingofuse:prepare_service` → `lingofuse:prepare_client` → `lingofuse:prepare_done` | `internal_call_<Api>` |
| Fortran | ✅ | ✅ | `lf_prepare_service` → `lf_prepare_client` → `lf_prepare_done` | `internal_call_<Api>` |
| Julia | ✅ | ✅ | `prepare_service` → `prepare_client` → `prepare_done` | `internal_call_<Api>` |
| R | ✅ | ✅ | `lingofuse::lf_prepare_service` → `lf_prepare_client` → `lf_prepare_done` | `internal_call_<Api>` |

### 8.2 Shutdown order

| Language | Shutdown order |
|------|----------|
| Pascal | `LF_ExitMainThread` → `LF_FreeApp` → `LF_Shutdown` |
| Python | `LF_ExitMainThread` → `app.free()` → `LF_Shutdown` |
| C++ | `exitMainThread` → App destructor → `shutdown` |
| C# | `NetworkEvents.Clear` → `ExitMainThread` → `app.Dispose` → `Shutdown` |
| Node.js | `exitMainThread` → `app.dispose()` → `shutdown` |
| TypeScript | `exitMainThread` → `app.dispose()` → `shutdown` |
| Rust | App Drop → library Drop |
| Go | `ExitMainThread` → `app.Close()` → `Shutdown` |
| Java | `NetworkEvents.clear` → `ExitMainThread` → `app.close()` → `Shutdown` |
| Dart | `app.dispose()` → `exitMainThread` → `shutdown` → `BridgeHost.instance.stop()` |
| Swift | `NetworkEvents.clearNetworkEvent` → `ExitMainThread` → `app.dispose()` → `Shutdown` → `LF_FreeLibrary` |
| Ruby | `exit_main_thread` → `app.dispose` → `shutdown` |
| Zig | `exitMainThread` → `app.deinit()` → `shutdown` |
| Erlang | `exit_main_thread` → `free_app` → `shutdown` |
| Fortran | `lf_exit_main_thread` → `lf_app_destroy` → `lf_shutdown` |
| Julia | `exit_main_thread` → `dispose!(app)` → `shutdown` |
| R | `lf_exit_main_thread` → `lf_free_app` → `lf_shutdown` |

### 8.3 Endpoints and App names

| Concept | Value |
|------|-----|
| LingoFuse endpoint | `ipc:<UnitName>_http_json` |
| Service App name | `<UnitName>` (after normalization) |
| Service App description | `HTTP/JSON service for <UnitName>` |
| Bridge App name | `__lf_http_bridge__` |
| Bridge API name | `__lf_outbound_post__` |

**The Service and the bridge must use the same endpoint string.**

---

## 9. Common integration problems

### 9.1 All languages

| Symptom | Cause | Fix |
|------|------|------|
| `prepareService` / `prepare_service` fails | the endpoint is already taken | change the endpoint or kill the old process |
| `prepareDone` / `prepare_done` returns 0 | already called in this process | restart the process |
| the App is not visible on the mesh | `Wait_Connection_ReadyOk` was not disabled | set it to `False` |
| the Service started but the Call cannot find it | the Service and bridge endpoints differ | unify the endpoint strings |
| the Service started but the Call still gets `Network error` | the bridge is not running | start `bridge.py` |
| it crashes on shutdown | the shutdown order is wrong | follow `exitMainThread → FreeApp → shutdown` |
| the process does not exit | the mesh thread was not joined | add `exitMainThread` or `exit!` |

### 9.2 Service-specific

| Symptom | Cause | Fix |
|------|------|------|
| `LF_LoadLibrary` returns something other than 1 | the LingoFuse native library is missing or the architecture is wrong | copy the correct `LingoFuse64.dll` / `liblingofuse.so` |
| `no found app("<Unit>")` (reported by the bridge) | the Service is not running | start the Service |
| `no found api("<Api>")` (reported by the bridge) | the API is not registered | check the `registerCall` calls |
| the stub function is never called | the user did not fill in `internal_call_<Api>` | fill in the business logic |
| the stub function returns 0 | the default stub returns 0 | replace it with the real logic |

### 9.3 Language-specific

| Language | Symptom | Cause | Fix |
|------|------|------|------|
| C# | `DllNotFoundException: LingoFuse64` | the DLL was not copied | copy it into the bin directory |
| C# | `Could not load type 'lingofuse.AppHandle'` | the LingoFuse.dll reference is missing | `dotnet add reference` |
| Java | `UnsatisfiedLinkError: LingoFuse64` | the native library is missing | add it to `-Djava.library.path` |
| Java | `ClassNotFoundException: jackson.databind.JsonNode` | Jackson is missing | download `jackson-databind.jar` |
| Ruby | `cannot load such file -- lingofuse` | the gem is not installed | `gem install lingofuse` |
| Ruby | the process does not exit | the `NativeBridge.start` thread was not joined | the generated code already forces exit with `exit!` |
| Zig | `std.array_list.Managed` compile error | the Zig version is too old | use Zig 0.13+ |
| Erlang | `no such file or directory: lingofuse_nif.dll` | the NIF is missing | copy it into `priv/` |
| Fortran | `undefined reference to 'lf_*'` | `lf_fortran.cpp` was not linked | use `setup_fortran_tests.ps1` |
| Julia | `--threads=2 or more required` | single-threaded | add `--threads=2` |
| Julia | `prepare_client returned -1` | the endpoint is already taken | change the endpoint or kill the old process |
| R | `The *_async variants require future::plan('sequential')` | an incompatible future plan | `future::plan(future::sequential)` |
| R | the process does not exit | the `lf_poll` loop does not stop | write the `service.exit` sentinel file |
| Dart | `prepareDone returned false` | `Wait_Connection_ReadyOk` was not disabled | set it to `False` |
| Swift | `libraryLoadFailed` | `liblingofuse.dylib` is missing | copy it next to the executable |

### 9.4 Quick reference on the Service–bridge relationship

| Question | Answer |
|------|------|
| **Does the Service need to go through the bridge?** | **No.** The Service is a mesh node and listens on the endpoint directly. |
| **Does the Service need the bridge running?** | **No.** The Service can start on its own (`--smoke` mode). |
| **Does the bridge need the Service running?** | **Yes.** The bridge is a client; it connects to the mesh endpoint and waits for the Service to register APIs. |
| **What do the Service and the bridge share?** | **The endpoint string** (`ipc:<UnitName>_http_json`). |
| **Should the Service start first or the bridge first?** | **Either.** The bridge is a client and can start after the Service. |
| **Can the bridge still be used after the Service stops?** | **No.** The bridge reports `no found app("<Unit>")`. |
| **Can the Service still be used after the bridge stops?** | **The Service itself still runs**, but **no Call can reach it** (because Call goes through the bridge). |
| **Can the Service use HTTP directly without the mesh?** | **No.** The service side must receive calls through the LingoFuse mesh. |

---

## Appendix: one-page quick reference

| Language | Has a service side | Needs the LingoFuse native library | Needs a LingoFuse language binding | Platform |
|------|:------------:|:--------------------:|:----------------------:|------|
| Pascal | ✅ | ✅ | ✅ `lingofuse_import` | Win / Linux / macOS |
| Python | ✅ | ✅ | ✅ the `lingofuse` Python package | Win / Linux / macOS |
| C++ | ✅ | ✅ | ✅ `LingoFuse.hpp` | Win / Linux / macOS |
| C# | ✅ | ✅ | ✅ the `LingoFuse` .NET binding | Win / Linux / macOS |
| **JavaScript** | ❌ | — | — | — |
| Node.js | ✅ | ✅ | ✅ `lingofuse-js` | Win / Linux / macOS |
| TypeScript | ✅ | ✅ | ✅ `lingofuse-ts` | Win / Linux / macOS |
| **PHP** | ❌ | — | — | — |
| Rust | ✅ | ✅ | ✅ the `lingofuse` crate | Win / Linux / macOS |
| Go | ✅ | ✅ | ✅ the `lingofuse` Go package | Win / Linux / macOS |
| Java | ✅ | ✅ | ✅ the `lingofuse` Java package | Win / Linux / macOS |
| **Delphi** | ❌ | — | — | — |
| Dart | ✅ | ✅ | ✅ the `lingofuse` Dart package | Win / Linux / macOS |
| Swift | ✅ | ✅ | ✅ the `lingofuse` Swift binding | macOS / Linux |
| Ruby | ✅ | ✅ | ✅ the `lingofuse` gem | Win / Linux / macOS |
| Zig | ✅ | ✅ | ✅ the `lingofuse` Zig binding | Win / Linux / macOS |
| Erlang | ✅ | ✅ | ✅ the `lingofuse` Erlang binding | Win / Linux / macOS |
| Fortran | ✅ | ✅ | ✅ `lf_fortran_mod` | Win / Linux / macOS |
| Julia | ✅ | ✅ | ✅ the `LingoFuse` Julia binding | Win / Linux / macOS |
| R | ✅ | ✅ | ✅ the `lingofuse` R package | Win / Linux / macOS |

**The Service does not need to go through the bridge.** The Service is a node of the LingoFuse mesh; it listens on the endpoint directly and waits for the bridge to turn an HTTP request into an LF_Call and deliver it. **The Service is upstream of the bridge, not downstream.**

**The service side must use the LingoFuse native library and a language binding.** That is the biggest difference from the call side — Call mode A does not need the native library, while the service side always does.

**The Service can only run on desktop / server platforms.** Mobile / embedded / WASM cannot run a Service. If you need to expose an interface to a mobile client, deploy the Service on a server and let the mobile client act as a Call through the bridge.
