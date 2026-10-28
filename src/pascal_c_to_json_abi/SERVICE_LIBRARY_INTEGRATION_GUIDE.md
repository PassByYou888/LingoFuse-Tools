# SERVICE 库接入方法指南

> 本文档给出 **每种目标语言** 对 **Service 库（服务侧）** 的接入方法。
>
> **Service 库是什么** — Service 库是"服务侧"产物，负责把一组本地函数注册为 **LingoFuse Call API**，接收来自 mesh 的 JSON 请求，调用内部业务逻辑，再把结果作为 JSON 响应返回。
>
> **Service 库的三条通用前提**：
>
> 1. **必须使用 LingoFuse 原生库**（`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`）与 `z_ipc_*`。
> 2. **必须使用 LingoFuse 语言绑定**（`lingofuse_import` / `lingofuse` Python 包 / `LingoFuse.hpp` / ...）。
> 3. **必须完成"三件套"初始化**：`prepareService` → `prepareClient` → `prepareDone`。
>
> **本文档的核心问题：Service 是否需要通过桥接？**
>
> **回答：不需要。** Service 是 LingoFuse mesh 的节点，它直接监听 mesh 端点，**不经过桥接**。桥接（`bridge.py` / `bridge.exe`）只服务于 **调用侧 → 服务侧** 这一个方向。
>
> 换句话说：
>
> - **Service** 是"被调用方"——它监听 mesh，等待 bridge 把 HTTP 请求转成 LF_Call 送到它这里。
> - **Bridge** 是"转发器"——它把调用侧的 HTTP 请求转成 LF_Call，发给 mesh 上的 Service。
> - **Service 是 bridge 的上游**，不是 bridge 的下游。**Service 不依赖 bridge，但 bridge 依赖 Service**。
>
> **因此**：启动 Service 时，**完全不需要 bridge 在运行**。Service 可以单独启动、单独测试（例如 `--smoke` 模式）。只要 Service 与 bridge 使用**同一个 endpoint**，bridge 上线后就能找到 Service。
>
> **关于语言支持的三个重要事实**：
>
> 1. **Service 侧必须用 LingoFuse 原生库**。所有 16+ 种支持 Service 的语言（Pascal / Python / C++ / C# / Node.js / TypeScript / Rust / Go / Java / Dart / Swift / Ruby / Zig / Erlang / Fortran / Julia / R）都依赖 LingoFuse 原生库。
> 2. **三种语言没有 Service 侧**：JavaScript（浏览器）、PHP、Delphi。这三种语言只能做 Call。
> 3. **平台支持受 LingoFuse 原生库限制**：Windows / Linux / macOS（桌面 / 服务器）。**不支持 iOS / Android / WASM / 嵌入式**——即使语言本身支持这些平台。

---

## 目录

1. [Service 库定位](#1-service-库定位)
2. [Service 不需要通过桥接](#2-service-不需要通过桥接)
3. [Service 的三件套初始化](#3-service-的三件套初始化)
4. [Service 的语言与平台支持](#4-service-的语言与平台支持)
5. [各语言接入详解](#5-各语言接入详解)
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
6. [无 Service 侧的语言](#6-无-service-侧的语言)
7. [平台与操作系统支持矩阵](#7-平台与操作系统支持矩阵)
8. [横向对比速查表](#8-横向对比速查表)
9. [常见集成问题](#9-常见集成问题)

---

## 1. Service 库定位

### 1.1 Service 库 = 服务侧

一个完整的接口对由 **Service（服务侧）** 与 **Call（调用侧）** 组成：

| 侧 | 职责 | 走桥接程序 |
|----|------|:----------:|
| **Service** | 把函数注册为 LingoFuse Call API，接收 JSON 请求并返回 JSON 响应 | ❌ **不走桥接** |
| **Call** | 把本地函数调用转为到桥接程序的请求，再把响应转回本地类型 | ✅ **必须走桥接** |

**关键不对称**：

- **Service 不依赖桥接**。Service 只依赖 LingoFuse mesh。
- **Call 依赖桥接**。Call 通过桥接访问 Service。

### 1.2 Service 库的产物命名

```
<UnitName>_http_json_service_<lang_suffix>.<ext>
```

| 语言 | Service 库文件名 |
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

**无 Service 侧的语言**：JavaScript（浏览器）、PHP、Delphi。

### 1.3 Service 库暴露的接口

每种语言的 Service 库都提供：

- **一个注册入口**（`registerAllAPIs` / `register_all_apis` / `RegisterAPIs` / `registerCall` 调用集合）。
- **一个 App 创建入口**（`CreateAndRegisterHTTPJsonApp` / `createAndRegisterHttpJsonApp` / `create_and_register_http_json_app` / `App(...)` 等）。
- **一个 `main` / `run_service` / `main()` 入口**（可直接作为可执行程序启动）。
- **每个支持 API 的 `internal_call_<Api>` 桩**（用户填业务逻辑）。

### 1.4 Service 与 Call 的差异

| 维度 | Service | Call |
|------|---------|------|
| **是否需要桥接** | ❌ 不需要 | ✅ 必须 |
| **是否需要 LingoFuse 原生库** | ✅ 必须 | 视语言而定（模式 A 不需要） |
| **是否需要 LingoFuse 语言绑定** | ✅ 必须 | 视语言而定 |
| **是否注册 API** | ✅ 是（`LF_RegisterCallEx` / `registerCall`） | ❌ 否 |
| **是否监听端点** | ✅ 是（`prepareService`） | ❌ 否（只 `prepareClient`） |
| **是否创建 App** | ✅ 是（`LF_CreateAppEx` / `App(...)`） | ❌ 否 |
| **核心用户代码** | `internal_call_<Api>` 桩（业务逻辑） | 调用生成函数（业务逻辑在别处） |
| **平台支持** | 受 LingoFuse 原生库限制 | 受语言 HTTP 客户端限制（模式 A 更广） |

---

## 2. Service 不需要通过桥接

### 2.1 完整拓扑

```
       ┌──────────────────────────────────────────────────┐
       │  Service 进程                                     │
       │  ─ 监听 ipc:<Unit>_http_json（prepareService）    │
       │  ─ 创建 App（LF_CreateAppEx）                     │
       │  ─ 注册 API（LF_RegisterCallEx）                  │
       │  ─ 作为 client 连到同一端点（prepareClient）      │
       │  ─ 启动 mesh（prepareDone）                       │
       └──────────────────────────────────────────────────┘
                          ▲
                          │ LF_Call（mesh 内部）
                          │
       ┌──────────────────────────────────────────────────┐
       │  Bridge 进程（bridge.py）                         │
       │  ─ 以 client 身份连到同一端点                    │
       │  ─ 注册 __lf_outbound_post__ 转发 API            │
       └──────────────────────────────────────────────────┘
                          ▲
                          │ HTTP POST
                          │
       ┌──────────────────────────────────────────────────┐
       │  Call 进程（任意语言）                            │
       │  ─ 直接 HTTP POST 到 bridge:8081                 │
       │  ─ 或通过 LingoFuse 调 __lf_outbound_post__       │
       └──────────────────────────────────────────────────┘
```

### 2.2 三个关键事实

1. **Service 不调用 bridge**。Service 只 `prepareService` + `prepareClient` + `prepareDone`，然后等 mesh 把 LF_Call 送到它。
2. **Bridge 主动连到 Service 所在的端点**。Bridge 是 client，Service 是 listener。Bridge 上线后自动发现 Service。
3. **Service 先启动、Bridge 后启动，完全没问题**。Bridge 是"客户端"角色；它可以晚于 Service 启动。反之，Service 晚于 Bridge 启动也没问题——Bridge 会在下一轮广播中重新发现 Service。

### 2.3 Service 独立运行完全可行

**`--smoke` 模式**：Service 完全不启动 mesh，只在进程内创建 `App`，通过 `local_call` 直接调用每个 API。

| 语言 | `--smoke` 模式入口 |
|------|-------------------|
| Pascal | `./<Unit>_http_json_service_main_test___ --smoke` |
| Python | `python3 <Unit>_http_json_service_main_test___.py --smoke` |
| C++ | 无（C++ 无 smoke 子命令） |
| C# | `dotnet run -- --smoke` |
| Node.js | `node <Unit>_http_json_service_main_test___.js --smoke` |
| TypeScript | `tsx <Unit>_http_json_service_main_test___.ts --smoke` |
| Rust | 直接运行 `cargo run`（无 smoke 子命令，需自己写） |
| Go | `go test -v` |
| Java | `java HttpJsonServiceTest --smoke` |
| Dart | 无（Dart 无 smoke 子命令） |
| Swift | `swift <Unit>_http_json_service_main_test___.swift --smoke` |
| Ruby | `ruby <Unit>_http_json_service_main_test___.rb --smoke` |
| Zig | 无（Zig 无 smoke 子命令） |
| Erlang | `escript <Unit>_http_json_service_main_test___.escript --smoke` |
| Fortran | `./service_test.exe --smoke` |
| Julia | `julia <Unit>_http_json_service_main_test___.jl --smoke` |
| R | 无（R 无 smoke 子命令，用 `parse()` 做语法检查） |

**`--smoke` 模式完全不需要 bridge**，因为它根本不走 mesh。

### 2.4 Service 与 Bridge 的唯一联系

**它们共享同一个 endpoint 字符串**：

```
ipc:<UnitName>_http_json
```

- Service 在 `prepareService(endpoint, endpoint)` 里监听它。
- Bridge 在 `bridge.py --endpoint <endpoint>` 里连到它。

**字符串必须完全一致**。不一致就找不到对方。

---

## 3. Service 的三件套初始化

所有 16+ 种语言的 Service 侧都遵循同一个初始化模式：

```
第 1 步：prepareService(endpoint, endpoint)
    ─ 监听 mesh 端点
    ─ 成为 beacon

第 2 步：创建 App + 注册 API
    ─ App = LF_CreateAppEx(name, desc)
    ─ for each API: LF_RegisterCallEx(App, api_name, desc, trigger, callback)
    ─ 或语言绑定的等价物

第 3 步：prepareClient(endpoint, App)
    ─ 也作为 client 连到同一端点
    ─ 这样其他 mesh 节点能路由到它

第 4 步：prepareDone()
    ─ 启动 mesh 事件循环
    ─ 返回 1 表示首次启动成功
```

**为什么需要 `prepareClient` 而不是只 `prepareService`？** 因为 LingoFuse 的路由模型要求"被调用的 App 必须作为 client 在 mesh 上可见"。`prepareService` 只是"监听端口"，`prepareClient` 才是"加入 mesh"。两者用同一个 endpoint，就形成"自我连接"。

### 3.1 顺序不可颠倒

| 步骤 | 必须在前 | 原因 |
|------|----------|------|
| `prepareService` | 第 1 位 | 没有监听的端口，后面的 `prepareClient` 无处可连 |
| `App` 创建 + API 注册 | 在 `prepareClient` 之前 | 注册必须在 client 连到 mesh 之前完成，否则 mesh 看不到 API |
| `prepareClient` | 在 `prepareDone` 之前 | `prepareDone` 启动 mesh 循环 |
| `prepareDone` | 最后 | 启动后就不能再注册新 API |

### 3.2 关闭顺序

```
第 1 步：exitMainThread()       ─ 停止 mesh 事件循环
第 2 步：FreeApp(app)           ─ 释放 App（自动注销 API）
第 3 步：shutdown()             ─ 释放 LingoFuse 原生库
```

**顺序不可颠倒**：先停 mesh，再注销 API，最后释放库。

---

## 4. Service 的语言与平台支持

### 4.1 支持 Service 的语言

| # | 语言 | 是否需要 LingoFuse 原生库 | 是否需要 LingoFuse 语言绑定 |
|:-:|------|:------------------------:|:---------------------------:|
| 1 | Pascal | ✅ | ✅ `lingofuse_import` |
| 2 | Python | ✅ | ✅ `lingofuse` Python 包 |
| 3 | C++ | ✅ | ✅ `LingoFuse.hpp` + `lf_io.hpp` |
| 4 | C# | ✅ | ✅ `LingoFuse` .NET 绑定 |
| 5 | Node.js | ✅ | ✅ `lingofuse-js` |
| 6 | TypeScript | ✅ | ✅ `lingofuse-ts` |
| 7 | Rust | ✅ | ✅ `lingofuse` crate |
| 8 | Go | ✅ | ✅ `github.com/PassByYou888/LingoFuse/go` |
| 9 | Java | ✅ | ✅ `lingofuse` Java 包 |
| 10 | Dart | ✅ | ✅ `lingofuse` Dart 包 |
| 11 | Swift | ✅ | ✅ `lingofuse` Swift 绑定 |
| 12 | Ruby | ✅ | ✅ `lingofuse` gem |
| 13 | Zig | ✅ | ✅ `lingofuse` Zig 绑定 |
| 14 | Erlang | ✅ | ✅ `lingofuse` Erlang binding |
| 15 | Fortran | ✅ | ✅ `lf_fortran_mod` |
| 16 | Julia | ✅ | ✅ `LingoFuse` Julia 绑定 |
| 17 | R | ✅ | ✅ `lingofuse` R 包 |

**全部 17 种语言都依赖 LingoFuse 原生库**。**没有"纯 HTTP Service"这种模式**——Service 侧永远是 LingoFuse mesh 节点。

### 4.2 不支持 Service 的语言

| 语言 | 原因 |
|------|------|
| **JavaScript（浏览器）** | 浏览器无法作为 LingoFuse mesh 节点（无法加载原生库） |
| **PHP** | PHP 无 LingoFuse 原生库支持 |
| **Delphi** | Delphi 的 `System.Net.HttpClient` 是纯 HTTP 客户端，无 LingoFuse 原生库绑定 |

这三种语言**只能做 Call**（见 `CALL_LIBRARY_INTEGRATION_GUIDE.md`）。

### 4.3 平台与操作系统

**所有 17 种语言的 Service 侧平台支持 = LingoFuse 原生库的支持范围**。

| 操作系统 | 支持 | 备注 |
|----------|:----:|------|
| **Windows（x86 / x64 / arm64）** | ✅ | 需要 `LingoFuse64.dll` + `z_ipc_64.dll` |
| **Linux（x64 / arm64）** | ✅ | 需要 `liblingofuse.so` + `libz_ipc_64.so` |
| **macOS（x64 / arm64）** | ✅ | 需要 `liblingofuse.dylib` |
| **iOS / iPadOS** | ❌ | LingoFuse 原生库不支持 |
| **Android** | ❌ | LingoFuse 原生库不支持 |
| **WASM** | ❌ | LingoFuse 原生库不支持 |
| **嵌入式（ARM Cortex-M 等）** | ❌ | LingoFuse 原生库不支持 |
| **FreeBSD / OpenBSD / NetBSD** | ❌ | LingoFuse 原生库不支持 |

**关键结论**：Service 只能运行在**桌面 / 服务器平台**。**移动端 / 嵌入式 / WASM 无法运行 Service**。如果需要在移动端提供接口，必须把 Service 部署在服务器上，让移动端作为 Call 通过桥接访问。

### 4.4 各语言 Service 侧的额外要求

| 语言 | 额外要求 |
|------|----------|
| Pascal | FPC 3.2+ 或 Delphi 11+ |
| Python | Python 3.8+ |
| C++ | C++17、CMake 3.15+ |
| C# | .NET 8.0+ |
| Node.js | Node 18+ |
| TypeScript | TS 5.0+、`tsx`、Node 18+ |
| Rust | Rust 1.70+ |
| Go | Go 1.21+（服务侧需 `CGO_ENABLED=1`） |
| Java | JDK 11+ |
| Dart | Dart 3.0+ |
| Swift | Swift 5.9+、macOS 12+ / Linux |
| Ruby | Ruby 2.7+ / 3.0+（gem 需 C 扩展工具链） |
| Zig | Zig 0.13+ |
| Erlang | Erlang/OTP 25+ |
| Fortran | gfortran 9+ / ifort / flang |
| Julia | Julia 1.9+、**必须 `--threads=2`** |
| R | R 4.0+ |

---

## 5. 各语言接入详解

### 5.1 Pascal

#### 5.1.1 产物

```
<Unit>_http_json_service_unit.pas
```

#### 5.1.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse_import.pas` | LingoFuse 发行版 | ✅ |
| `Z.Core`、`Z.PascalStrings`、`Z.UPascalStrings`、`Z.UnicodeMixedLib`、`Z.Json` | Z 框架 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` / `libz_ipc_64.so` | LingoFuse 发行版 | ✅（运行时） |

#### 5.1.3 平台

- **编译器**：FPC 3.2+ / Delphi 11+。
- **OS**：Windows（x86/x64/arm64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.1.4 初始化

```pascal
uses
  lingofuse_import,
  <Unit>_http_json_service_unit;

var
  App: TAppHnd___;
begin
  // 1. 加载 LingoFuse 原生库
  if LF_LoadLibrary() <> 1 then
  begin
    WriteLn('Failed to load LingoFuse');
    Halt(1);
  end;

  // 2. 监听端点
  LF_PrepareServiceEx('ipc:<Unit>_http_json', 'ipc:<Unit>_http_json');

  // 3. 创建 App + 注册 API
  App := CreateAndRegisterHTTPJsonApp;
  if App = nil then
  begin
    WriteLn('Failed to create app');
    Halt(1);
  end;

  // 4. 作为 client 连到同一端点
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

#### 5.1.5 填业务逻辑

**在生成的 `<Unit>_http_json_service_unit.pas` 里**，找到 `internal_call_<Api>` 桩，把 `TODO` 替换为真实调用：

```pascal
function internal_call_Add_Add(a: Int64; b: Int64): Int64;
begin
  // TODO: call the real function, for example:
  //   Result := Add(a, b);
  Result := 0;  // ← 替换这里
end;
```

**推荐做法**：把业务逻辑放在独立单元 `CalculatorImpl.pas` 里，桩里只做 `Result := CalculatorImpl.Add(a, b);`。这样重新生成服务单元时业务逻辑不丢。

#### 5.1.6 关闭

```pascal
LF_ExitMainThread;
LF_FreeApp(App);
LF_Shutdown;
```

#### 5.1.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `LF_PrepareServiceEx` 失败 | 端点已被占用 | 换端点或杀旧进程 |
| `LF_PrepareDone` 返回 0 | 同一进程已调用过 | 重启进程 |
| `no found app("<Unit>")`（bridge 报） | Service 未启动 | 启动 Service |

---

### 5.2 Python

#### 5.2.1 产物

```
<Unit>_http_json_service.py
```

#### 5.2.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse` Python 包 | LingoFuse 发行版 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| Python 3.8+ | — | ✅ |

#### 5.2.3 平台

- **运行时**：Python 3.8+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.2.4 初始化

**生成的 `main()` 已包含完整初始化流程**，直接运行即可：

```bash
python3 <Unit>_http_json_service.py
```

**或在你自己的代码里显式初始化**：

```python
from lingofuse._lf_native import (
    LF_ResetPrepare, LF_PrepareService, LF_PrepareClient, LF_PrepareDone,
    LF_CreateAppEx, LF_RegisterCallEx, LF_ExitMainThread, LF_Shutdown
)
from lingofuse.lf_io import cstr

ENDPOINT = "ipc:<Unit>_http_json"

# 1. 配置
LF_SetOptionEx("Wait_Connection_ReadyOk", "False")
LF_SetOptionEx("Overlap_Connection", "True")
LF_ResetPrepare()

# 2. 监听端点
LF_PrepareService(cstr(ENDPOINT), cstr(ENDPOINT))

# 3. 创建 App + 注册 API
app = LF_CreateAppEx(cstr("<Unit>"), cstr("HTTP/JSON service for <Unit>"))
LF_RegisterCallEx(app, cstr("Add"), cstr("Adds two integers"), nil, callback_add)
LF_RegisterCallEx(app, cstr("Sub"), cstr("Subtracts b from a"), nil, callback_sub)

# 4. 作为 client 连到同一端点
LF_PrepareClient(cstr(ENDPOINT), app)
if LF_PrepareDone() != 1:
    raise RuntimeError("prepare_done failed")

# 5. 等待 Ctrl+C
import signal
signal.pause()

# 6. 关闭
LF_ExitMainThread()
app.free()
LF_Shutdown()
```

#### 5.2.5 填业务逻辑

**在生成的 `<Unit>_http_json_service.py` 里**，找到 `internal_call_<Api>` 桩：

```python
def internal_call_Add(a: int, b: int) -> int:
    """
    HTTP/JSON API: Add.
    TODO: replace the body with a call to the real implementation.
    Suggested call: Add(a, b)
    """
    # TODO: implement this stub.
    return 0  # ← 替换这里
```

**推荐做法**：新建 `calculator_impl.py`，桩里做 `from calculator_impl import add` + `return add(a, b)`。

#### 5.2.6 关闭

```python
LF_ExitMainThread()
app.free()
LF_Shutdown()
```

#### 5.2.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `ModuleNotFoundError: lingofuse` | 未安装 LingoFuse Python 包 | 装 LingoFuse 发行版 |
| `prepare_service` 返回 -1 | 端点已被占用 | 换端点或杀旧进程 |
| `prepare_done` 返回 0 | 同一进程已调用过 | 重启进程 |

---

### 5.3 C++

#### 5.3.1 产物

```
<Unit>_http_json_service.hpp
<Unit>_http_json_service.cpp
```

#### 5.3.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `LingoFuse.h`、`LingoFuse.c` | LingoFuse 发行版 | ✅ |
| `LingoFuse.hpp`、`lf_io.hpp` | LingoFuse 发行版 | ✅ |
| `json.hpp`（nlohmann） | LingoFuse 发行版或单独获取 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| C++17 编译器 | — | ✅ |
| CMake 3.15+ | — | 推荐 |

#### 5.3.3 平台

- **编译器**：MSVC 2019+ / g++ 9+ / clang++ 10+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.3.4 初始化

**生成的 `run_service()` 已包含完整流程**，直接 `main()` 调用即可：

```bash
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
./build/<Unit>_http_json_service
```

**`run_service()` 的核心流程**：

```cpp
int run_service() {
    // 1. 加载 LingoFuse 原生库（RAII）
    lingofuse::LibraryLoader loader;

    // 2. 配置
    lingofuse::setOption("Wait_Connection_ReadyOk", "False");
    lingofuse::setOption("Overlap_Connection", "True");
    lingofuse::resetPrepare();

    // 3. 监听端点
    if (lingofuse::prepareService("<Unit>_http_json_endpoint",
                                  "<Unit>_http_json_endpoint") < 0) {
        return 1;
    }

    // 4. 创建 App + 注册 API + 作为 client 连到同一端点
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

        // 等待 Ctrl+C
        std::signal(SIGINT, _on_signal);
        while (!g_stop_requested.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }

        lingofuse::exitMainThread();
    }
    // App 析构，自动 FreeApp

    lingofuse::shutdown();
    return 0;
}
```

#### 5.3.5 填业务逻辑

**在生成的 `<Unit>_http_json_service.cpp` 里**，找到 `internal_call_<Api>` 桩：

```cpp
std::int64_t internal_call_Add(std::int64_t a, std::int64_t b) {
    // TODO: implement this stub.
    // Suggested call: Add(a, b);
    return 0;  // ← 替换这里
}
```

**推荐做法**：新建 `calculator_impl.hpp` / `.cpp`，桩里 `return calculator_impl::add(a, b);`。

#### 5.3.6 关闭

```cpp
lingofuse::exitMainThread();
// App 析构自动 FreeApp
lingofuse::shutdown();
// LibraryLoader 析构自动 LF_FreeLibrary
```

#### 5.3.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `LF_PrepareService failed` | 端点已被占用 | 换端点或杀旧进程 |
| `LF_PrepareDone failed` | 同一进程已调用过 | 重启进程 |
| 链接器找不到 `LingoFuse` | DLL 未复制 | 复制 DLL 到可执行文件旁 |

---

### 5.4 C#

#### 5.4.1 产物

```
<Unit>_http_json_service.cs
```

#### 5.4.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `LingoFuse` .NET 绑定（`LingoFuse.dll`） | LingoFuse 发行版 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| .NET 8.0+ | — | ✅ |

#### 5.4.3 平台

- **运行时**：.NET 8.0+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.4.4 初始化

**生成的 `Service.RunService()` 已包含完整流程**：

```csharp
// 你的 Program.cs
using <Unit>_http_json_service;

class Program
{
    static int Main(string[] args) => Service.RunService();
}
```

**`RunService()` 的核心流程**：

```csharp
public static int RunService()
{
    // 1. 配置
    Framework.SetOption("Wait_Connection_ReadyOk", "False");
    Framework.SetOption("Overlap_Connection", "True");
    Framework.ResetPrepare();

    // 2. 监听端点
    if (Framework.PrepareService(AppInfo.Endpoint, AppInfo.Endpoint) < 0)
    {
        Console.Error.WriteLine("[FATAL] PrepareService failed");
        return 1;
    }

    // 3. 创建 App + 注册 API + 作为 client 连到同一端点
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
        // 4. 关闭（顺序不可颠倒）
        try { NetworkEvents.Clear(); } catch { }
        try { Framework.ExitMainThread(); } catch { }
        try { app?.Dispose(); } catch { }
        try { Framework.Shutdown(); } catch { }
    }
}
```

#### 5.4.5 填业务逻辑

**在生成的 `<Unit>_http_json_service.cs` 里**，找到 `InternalCalls` 类的每个桩：

```csharp
public static class InternalCalls
{
    public static long Add(long a, long b)
    {
        // TODO: replace the body with a call to the real implementation.
        // Suggested call: Add(a, b);
        return 0;  // ← 替换这里
    }
}
```

**推荐做法**：新建 `CalculatorImpl.cs`，桩里 `return CalculatorImpl.Add(a, b);`。

#### 5.4.6 关闭

```csharp
try { NetworkEvents.Clear(); } catch { }
try { Framework.ExitMainThread(); } catch { }
try { app?.Dispose(); } catch { }
try { Framework.Shutdown(); } catch { }
```

#### 5.4.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `DllNotFoundException: LingoFuse64` | DLL 未复制 | 复制到 bin 目录 |
| `Could not load type 'lingofuse.AppHandle'` | LingoFuse.dll 引用缺失 | `dotnet add reference` |
| `PrepareService failed` | 端点已被占用 | 换端点或杀旧进程 |

---

### 5.5 Node.js

#### 5.5.1 产物

```
<Unit>_http_json_service_node.js
```

#### 5.5.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse-js` | npm | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| Node.js 18+ | — | ✅ |

#### 5.5.3 平台

- **运行时**：Node.js 18+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.5.4 初始化

**生成的 `main()` 已包含完整流程**：

```bash
node <Unit>_http_json_service_node.js
```

**`main()` 的核心流程**：

```javascript
function main() {
    // 1. 配置
    framework.setOption('Wait_Connection_ReadyOk', 'False');
    framework.setOption('Overlap_Connection', 'True');
    framework.resetPrepare();

    // 2. 监听端点
    if (framework.prepareService(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT) < 0) {
        console.error('[FATAL] prepareService failed');
        return 1;
    }

    // 3. 创建 App + 注册 API + 作为 client 连到同一端点
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

    // 4. 等待 Ctrl+C
    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));
    setInterval(() => {}, 1 << 30);
    return 0;
}
```

#### 5.5.5 填业务逻辑

**在生成的 `<Unit>_http_json_service_node.js` 里**，找到 `internal_call_<Api>` 桩：

```javascript
function internal_call_Add(a, b) {
    // TODO: implement this stub.
    return 0;  // ← 替换这里
}
```

**推荐做法**：新建 `calculator_impl.js`，桩里 `return require('./calculator_impl').add(a, b);`。

#### 5.5.6 关闭

```javascript
framework.exitMainThread();
app.dispose();
framework.shutdown();
```

#### 5.5.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Cannot find module 'lingofuse-js'` | 未安装 | `npm install lingofuse-js` |
| `prepareService failed` | 端点已被占用 | 换端点或杀旧进程 |
| `prepareDone failed` | 同一进程已调用过 | 重启进程 |

---

### 5.6 TypeScript

#### 5.6.1 产物

```
<Unit>_http_json_service.ts
```

#### 5.6.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse-ts` | npm | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| TypeScript 5.0+ | npm | ✅ |
| `tsx` | npm | ✅（直接运行 .ts） |
| Node.js 18+ | — | ✅ |

#### 5.6.3 平台

- **运行时**：Node.js 18+（通过 `tsx`）。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.6.4 初始化

**生成的 `main()` 已包含完整流程**：

```bash
./node_modules/.bin/tsx.cmd <Unit>_http_json_service.ts
```

**`main()` 的核心流程**：

```typescript
export function main(): number {
    // 1. 配置
    lf.options.setOptWaitConnectionReadyOk(false);
    lf.options.setOptOverlapConnection(true);
    lf.framework.resetPrepare();

    // 2. 监听端点
    if (lf.framework.prepareService(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT) < 0) {
        console.error(`[FATAL] prepareService failed`);
        return 1;
    }

    // 3. 创建 App + 注册 API + 作为 client 连到同一端点
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

    // 4. 等待 Ctrl+C
    process.on("SIGINT", () => shutdown("SIGINT"));
    process.on("SIGTERM", () => shutdown("SIGTERM"));
    setInterval(() => {}, 1 << 30);
    return 0;
}
```

#### 5.6.5 填业务逻辑

**在生成的 `<Unit>_http_json_service.ts` 里**，找到 `internal_call_<Api>` 桩：

```typescript
export function internal_call_Add(a: number, b: number): number {
    // TODO: implement this stub.
    return 0;  // ← 替换这里
}
```

**推荐做法**：新建 `calculator_impl.ts`，桩里 `return calculator_impl.add(a, b);`。

#### 5.6.6 关闭

```typescript
try { lf.network.clearNetworkEvent(); } catch { }
try { lf.AsyncBridge.shutdownInstance(); } catch { }
try { lf.framework.exitMainThread(); } catch { }
try { app?.dispose(); } catch { }
try { lf.framework.shutdown(); } catch { }
```

#### 5.6.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Cannot find module 'lingofuse-ts'` | 未安装 | `npm install lingofuse-ts` |
| `tsx: not found` | 未安装 | `npm install tsx` |
| `prepareService failed` | 端点已被占用 | 换端点或杀旧进程 |

---

### 5.7 Rust

#### 5.7.1 产物

```
<Unit>_http_json_service_rs.rs
```

#### 5.7.2 依赖

**`Cargo.toml`**：

```toml
[dependencies]
lingofuse = { path = "../LingoFuse/rust" }
serde_json = "1"
```

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse` crate | LingoFuse 发行版 | ✅ |
| `serde_json` | crates.io | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| Rust 1.70+ | — | ✅ |

#### 5.7.3 平台

- **编译器 / 运行时**：Rust 1.70+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.7.4 初始化

**生成的 `run_service()` 已包含完整流程**：

```bash
cargo new my_service
cd my_service
cargo add lingofuse --path ../LingoFuse/rust
cargo add serde_json
cp ../<Unit>_http_json_service_rs.rs src/main.rs
cargo run
```

**`run_service()` 的核心流程**：

```rust
pub fn run_service() -> Result<AppHandle, Box<dyn std::error::Error>> {
    println!("=== {} HTTP/JSON service ===", APP_NAME);

    // 1. 创建 App
    let app = AppHandle::new(APP_NAME, APP_DESC)?;

    // 2. 注册 API
    register_all_apis(&app)?;

    // 3. 配置
    framework::set_option("Wait_Connection_ReadyOk", "False")?;
    framework::set_option("Overlap_Connection", "True")?;
    framework::reset_prepare();

    // 4. 监听端点
    let serv_tag = framework::prepare_service(ENDPOINT, ENDPOINT)?;
    if serv_tag < 0 {
        return Err(format!("prepare_service failed: {}", serv_tag).into());
    }

    // 5. 作为 client 连到同一端点
    let cli_tag = framework::prepare_client(ENDPOINT, Some(&app))?;
    if cli_tag < 0 {
        return Err(format!("prepare_client failed: {}", cli_tag).into());
    }

    // 6. 启动 mesh
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

#### 5.7.5 填业务逻辑

**在生成的 `<Unit>_http_json_service_rs.rs` 里**，找到 `internal_call_<Api>` 桩：

```rust
pub fn internal_call_Add(a: i64, b: i64) -> i64 {
    let _ = (a, b);
    // TODO: replace this body with the real implementation.
    0  // ← 替换这里
}
```

**推荐做法**：新建 `calculator_impl.rs`，桩里 `calculator_impl::add(a, b)`。

#### 5.7.6 关闭

```rust
// App 的 Drop 自动 FreeApp
// LingoFuse 原生库的卸载由 lingofuse crate 的 Drop 处理
```

#### 5.7.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `lingofuse not found` | 未 `cargo add` | `cargo add lingofuse --path ../LingoFuse/rust` |
| `linking with cc failed` | 缺 C 链接器 | 装 MSVC Build Tools 或 gcc |
| `prepare_service failed` | 端点已被占用 | 换端点或杀旧进程 |

---

### 5.8 Go

#### 5.8.1 产物

```
<Unit>_http_json_service_go.go
```

#### 5.8.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `github.com/PassByYou888/LingoFuse/go` | GitHub | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| Go 1.21+ | — | ✅ |
| `CGO_ENABLED=1` | — | ✅（服务侧需要 cgo） |

#### 5.8.3 平台

- **运行时**：Go 1.21+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。**移动端 / WASM 因需要 cgo 而不可用**。

#### 5.8.4 初始化

**生成的 `runService()` 已包含完整流程**：

```bash
go mod init my_service
go get github.com/PassByYou888/LingoFuse/go
cp ../<Unit>_http_json_service_go.go .
cp ../<Unit>_http_json_service_main_test.go .
CGO_ENABLED=1 go test -v
```

**`runService()` 的核心流程**：

```go
func runService() error {
    fmt.Println("=== " + AppName + " HTTP/JSON service ===")

    // 1. 创建 App
    app, err := lingofuse.NewAppHandle(AppName, AppDesc)
    if err != nil {
        return fmt.Errorf("create app: %w", err)
    }
    defer func() {
        _ = lingofuse.ExitMainThread()
        app.Close()
        _ = lingofuse.Shutdown()
    }()

    // 2. 注册 API
    if err := registerAllAPIs(app); err != nil {
        return err
    }

    // 3. 配置
    if err := lingofuse.SetOption("Wait_Connection_ReadyOk", "False"); err != nil {
        return err
    }
    if err := lingofuse.SetOption("Overlap_Connection", "True"); err != nil {
        return err
    }
    if err := lingofuse.ResetPrepare(); err != nil {
        return err
    }

    // 4. 监听端点
    if _, err := lingofuse.PrepareService(Endpoint, Endpoint); err != nil {
        return fmt.Errorf("PrepareService: %w", err)
    }

    // 5. 作为 client 连到同一端点
    if _, err := lingofuse.PrepareClient(Endpoint, app); err != nil {
        return fmt.Errorf("PrepareClient: %w", err)
    }

    // 6. 启动 mesh
    started, err := lingofuse.PrepareDone()
    if err != nil {
        return fmt.Errorf("PrepareDone: %w", err)
    }
    if !started {
        return fmt.Errorf("PrepareDone returned false")
    }

    fmt.Println("[OK] Service ready. Press Ctrl+C to stop.")

    // 7. 等待信号
    sigCh := make(chan os.Signal, 1)
    signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
    <-sigCh
    return nil
}
```

#### 5.8.5 填业务逻辑

**在生成的 `<Unit>_http_json_service_go.go` 里**，找到 `internalCall<Api>` 桩：

```go
func internalCallAdd(a int64, b int64) (int64, error) {
    _ = a
    _ = b
    // TODO: replace this body with the real implementation.
    return 0, nil  // ← 替换这里
}
```

**推荐做法**：新建 `calculator_impl.go`，桩里 `return calculator_impl.Add(a, b)`。

#### 5.8.6 关闭

```go
defer func() {
    _ = lingofuse.ExitMainThread()
    app.Close()
    _ = lingofuse.Shutdown()
}()
```

#### 5.8.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `module github.com/PassByYou888/LingoFuse not found` | 未 `go get` | `go get github.com/PassByYou888/LingoFuse/go` |
| cgo 相关错误 | `CGO_ENABLED=0` | `CGO_ENABLED=1 go build` |
| `PrepareService failed` | 端点已被占用 | 换端点或杀旧进程 |

---

### 5.9 Java

#### 5.9.1 产物

```
HttpJsonService.java
```

#### 5.9.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse` Java 包 | LingoFuse 发行版 | ✅ |
| `jackson-databind.jar` | Maven Central | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| JDK 11+ | — | ✅ |

#### 5.9.3 平台

- **运行时**：JDK 11+（推荐 17+）。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.9.4 初始化

**生成的 `main()` 已包含完整流程**：

```bash
javac -cp lingofuse.jar:jackson-databind.jar *.java
java --enable-native-access=ALL-UNNAMED \
     -cp .:lingofuse.jar:jackson-databind.jar \
     HttpJsonService
```

**`main()` 的核心流程**：

```java
public static void main(String[] args) {
    System.out.println("=== " + HTTP_SERVICE_APP_NAME + " HTTP/JSON service ===");
    System.out.println("Endpoint: " + HTTP_SERVICE_ENDPOINT);

    AppHandle app = null;
    boolean started = false;

    try {
        // 1. 配置
        Framework.setOption("Wait_Connection_ReadyOk", "False");
        Framework.setOption("Overlap_Connection", "True");
        Framework.resetPrepare();

        // 2. 创建 App + 注册 API
        app = createAndRegister();

        // 3. 监听端点
        int servRet = Framework.prepareService(
            HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT);
        if (servRet < 0) {
            System.err.println("[FATAL] prepareService failed");
            throw new RuntimeException("prepareService failed");
        }

        // 4. 作为 client 连到同一端点
        int clientRet = Framework.prepareClient(HTTP_SERVICE_ENDPOINT, app);
        if (clientRet < 0) {
            System.err.println("[FATAL] prepareClient failed");
            throw new RuntimeException("prepareClient failed");
        }

        // 5. 启动 mesh
        int doneRet = Framework.prepareDone();
        if (doneRet != 1 && !LingoFuseStatus.checkMainThread()) {
            System.err.println("[FATAL] prepareDone failed");
            throw new RuntimeException("prepareDone failed");
        }
        started = true;

        System.out.println("[OK] Service ready. Press Ctrl+C to stop.");

        // 6. 等待 Ctrl+C
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

#### 5.9.5 填业务逻辑

**在生成的 `HttpJsonService.java` 里**，找到 `internalCall_<Api>` 桩：

```java
private static long internalCall_Add(long a, long b) {
    // TODO: implement this stub.
    // Suggested call: Add(a, b)
    return 0L;  // ← 替换这里
}
```

**推荐做法**：新建 `CalculatorImpl.java`，桩里 `return CalculatorImpl.Add(a, b);`。

#### 5.9.6 关闭

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

#### 5.9.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `UnsatisfiedLinkError: LingoFuse64` | 原生库缺失 | 加到 `-Djava.library.path` |
| `ClassNotFoundException: lingofuse.AppHandle` | `lingofuse.jar` 缺失 | 装 LingoFuse Java 包 |
| `ClassNotFoundException: jackson.databind.JsonNode` | Jackson 缺失 | 下载 `jackson-databind.jar` |
| `prepareService failed` | 端点已被占用 | 换端点或杀旧进程 |

---

### 5.10 Dart

#### 5.10.1 产物

```
<Unit>_http_json_service.dart
```

#### 5.10.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse` Dart 包 | LingoFuse 发行版 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| Dart 3.0+ | — | ✅ |

#### 5.10.3 平台

- **运行时**：Dart 3.0+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。**移动端因需要 LingoFuse 原生库而不可用**。

#### 5.10.4 初始化

**生成的 `main()` 已包含完整流程**：

```bash
dart run <Unit>_http_json_service.dart
```

**`main()` 的核心流程**：

```dart
Future<void> main(List<String> args) async {
    print('=== $HTTP_SERVICE_APP_NAME HTTP/JSON service ===');
    print('Endpoint: $HTTP_SERVICE_ENDPOINT');

    // 1. 启动 C bridge（Dart 特有：BridgeHost）
    await BridgeHost.start();

    // 2. 创建 App + 注册 API
    final app = AppHandle(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC);
    register_all_http_json_apis(app);

    // 3. 配置
    Framework.setOption('Quiet', 'True');
    Framework.setOption('Wait_Connection_ReadyOk', 'False');
    Framework.setOption('Overlap_Connection', 'True');
    Framework.resetPrepare();

    // 4. 监听端点 + 作为 client 连到同一端点
    Framework.prepareService(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT);
    Framework.prepareClient(HTTP_SERVICE_ENDPOINT, app: app);

    // 5. 启动 mesh
    if (!Framework.prepareDone()) {
        stderr.writeln('[FATAL] prepareDone failed');
        await _shutdown(app);
        exit(1);
    }

    // 6. 等待 mesh 可见
    bool visible = false;
    for (int i = 0; i < 30; i++) {
        if (Framework.checkApp(HTTP_SERVICE_APP_NAME)) {
            visible = true;
            break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
    }

    print('[OK] Service ready. Press Ctrl+C to stop.');

    // 7. 等待 Ctrl+C
    await _waitForShutdown();

    // 8. 关闭
    await _shutdown(app);
}
```

#### 5.10.5 填业务逻辑

**在生成的 `<Unit>_http_json_service.dart` 里**，找到 `internal_call_<Api>` 桩：

```dart
int internal_call_Add(int a, int b) {
    // TODO: implement this stub.
    return 0;  // ← 替换这里
}
```

**推荐做法**：新建 `calculator_impl.dart`，桩里 `return calculator_impl.add(a, b);`。

#### 5.10.6 关闭

```dart
Future<void> _shutdown(AppHandle app) async {
    try { app.dispose(); } catch (_) {}
    try { Framework.exitMainThread(); } catch (_) {}
    try { Framework.shutdown(); } catch (_) {}
    try { BridgeHost.instance.stop(); } catch (_) {}
}
```

#### 5.10.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Error: Couldn't resolve the package 'lingofuse'` | 未 `dart pub get` | `dart pub get` |
| `prepareDone returned false` | `Wait_Connection_ReadyOk` 未关 | 设置 `False` |
| `prepareService failed` | 端点已被占用 | 换端点或杀旧进程 |

---

### 5.11 Swift

#### 5.11.1 产物

```
<Unit>_http_json_service_swift.swift
```

#### 5.11.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse` Swift 绑定 | LingoFuse 发行版 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| Swift 5.9+ | — | ✅ |

#### 5.11.3 平台

- **编译器 / 运行时**：Swift 5.9+。
- **OS**：macOS 12+、Linux。**iOS 因需要 LingoFuse 原生库而不可用**。

#### 5.11.4 初始化

**生成的 `runService()` 已包含完整流程**：

```bash
swift <Unit>_http_json_service.swift
```

**`runService()` 的核心流程**：

```swift
public static func runService() throws -> AppHandle {
    // 1. 加载 LingoFuse 原生库
    guard LF_LoadLibrary() == 1 else {
        throw ServiceError.libraryLoadFailed
    }

    // 2. 配置
    Framework.setOption("Wait_Connection_ReadyOk", "False")
    Framework.setOption("Overlap_Connection", "True")
    Framework.setOption("Quiet", debugLog ? "False" : "True")
    Framework.resetPrepare()

    // 3. 监听端点
    do {
        _ = try Framework.prepareService(
            listeningAddr: endpoint,
            physicsAddr: endpoint)
    } catch {
        throw ServiceError.prepareServiceFailed("\(error)")
    }

    // 4. 创建 App + 注册 API
    let app = try AppHandle(name: appName, description: appDescription)
    try registerAllApis(app)

    // 5. 作为 client 连到同一端点
    do {
        _ = try Framework.prepareClient(physicsAddr: endpoint, app: app)
    } catch {
        app.dispose()
        throw ServiceError.prepareClientFailed("\(error)")
    }

    // 6. 启动 mesh
    if !Framework.prepareDone() && !Framework.checkMainThread() {
        app.dispose()
        throw ServiceError.prepareDoneFailed
    }

    return app
}
```

#### 5.11.5 填业务逻辑

**在生成的 `<Unit>_http_json_service_swift.swift` 里**，找到 `internal_call_<Api>` 桩：

```swift
public static func internal_call_Add(_ a: Int64, _ b: Int64) -> Int64 {
    _ = (a, b)
    // TODO: replace this body with the real implementation.
    return 0  // ← 替换这里
}
```

**推荐做法**：新建 `CalculatorImpl.swift`，桩里 `return CalculatorImpl.add(a, b)`。

#### 5.11.6 关闭

```swift
NetworkEvents.clearNetworkEvent()
Framework.exitMainThread()
app.dispose()
Framework.shutdown()
LF_FreeLibrary()
```

#### 5.11.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `libraryLoadFailed` | LingoFuse64.dylib 缺失 | 复制到可执行文件旁 |
| `prepareServiceFailed` | 端点已被占用 | 换端点或杀旧进程 |
| `prepareDoneFailed` | 同一进程已调用过 | 重启进程 |

---

### 5.12 Ruby

#### 5.12.1 产物

```
<Unit>_http_json_service.rb
<Unit>_http_json_service_impl.rb（如适用）
```

#### 5.12.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse` gem | RubyGems / LingoFuse 发行版 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| Ruby 2.7+ / 3.0+ | — | ✅ |

#### 5.12.3 平台

- **运行时**：Ruby 2.7+ / 3.0+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.12.4 初始化

**生成的 `main()` 已包含完整流程**：

```bash
gem install lingofuse  # 仅需一次
ruby <Unit>_http_json_service.rb
```

**`main()` 的核心流程**：

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

    # 1. 监听端点
    begin
        LingoFuse::Framework.prepare_service(ENDPOINT, ENDPOINT)
    rescue StandardError => e
        warn "[FATAL] prepare_service failed: #{e.message}"
        return 1
    end

    # 2. 创建 App + 注册 API
    app = begin
        create_and_register_http_json_app
    rescue StandardError => e
        warn "[FATAL] create_and_register failed: #{e.message}"
        return 1
    end
    return 1 if app.nil?

    # 3. 作为 client 连到同一端点
    begin
        LingoFuse::Framework.prepare_client(ENDPOINT, app)
    rescue StandardError => e
        warn "[FATAL] prepare_client failed: #{e.message}"
        app.dispose rescue nil
        return 1
    end

    # 4. 启动 mesh
    unless LingoFuse::Framework.prepare_done
        warn "[FATAL] prepare_done failed"
        app.dispose rescue nil
        return 1
    end

    $stdout.puts '[OK] Service ready. Press Ctrl+C to stop.'

    # 5. 等待 Ctrl+C
    stop = false
    prev_int = trap('INT') { stop = true }
    begin
        until stop
            sleep(0.5)
        end
    rescue Interrupt
        stop = true
    end

    # 6. 关闭
    LingoFuse::Framework.exit_main_thread rescue nil
    app.dispose rescue nil
    LingoFuse::Framework.shutdown rescue nil
    $stdout.puts 'Service stopped.'
    0
end
```

#### 5.12.5 填业务逻辑

**在生成的 `<Unit>_http_json_service.rb` 里**，找到 `internal_call_<Api>` 桩：

```ruby
def self.internal_call_add(a, b)
    # TODO: replace this body with the real implementation.
    0  # ← 替换这里
end
```

**推荐做法**：新建 `calculator_impl.rb`，桩里 `CalculatorImpl.add(a, b)`。

#### 5.12.6 关闭

```ruby
LingoFuse::Framework.exit_main_thread rescue nil
app.dispose rescue nil
LingoFuse::Framework.shutdown rescue nil
```

#### 5.12.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `cannot load such file -- lingofuse` | gem 未安装 | `gem install lingofuse` |
| `prepare_service failed` | 端点已被占用 | 换端点或杀旧进程 |
| 进程不退出 | `NativeBridge` 线程未 join | 生成代码已用 `exit!` 强制退出 |

---

### 5.13 Zig

#### 5.13.1 产物

```
<Unit>_http_json_service_zig.zig
```

#### 5.13.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse` Zig 绑定（`src/lingofuse.zig`） | LingoFuse 发行版 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| Zig 0.13+ | — | ✅ |

#### 5.13.3 平台

- **编译器**：Zig 0.13+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.13.4 初始化

**生成的 `runService()` 已包含完整流程**：

```bash
cd zig_service_test
zig build run
```

**`runService()` 的核心流程**：

```zig
pub fn runService() !void {
    // 1. 加载 LingoFuse
    try lf.framework.init();
    errdefer lf.framework.deinit();

    // 2. 配置
    lf.options.setWaitConnectionReadyOk(false) catch {};
    lf.options.setOverlapConnection(true) catch {};
    lf.options.setQuiet(true) catch {};
    lf.framework.resetPrepare();

    // 3. 创建 App + 注册 API
    var app = try lf.AppHandle.create(APP_NAME, APP_DESC);
    errdefer app.deinit();
    try registerAllApis(&app);

    // 4. 监听端点 + 作为 client 连到同一端点
    _ = try lf.framework.prepareService(ENDPOINT, ENDPOINT);
    _ = try lf.framework.prepareClient(ENDPOINT, &app);

    // 5. 启动 mesh
    _ = lf.framework.prepareDone();

    std.debug.print("[service] Online on endpoint {s}\n", .{ENDPOINT});
    std.debug.print("[service] Press Enter to stop.\n", .{});
    _ = getchar();

    // 6. 关闭
    lf.framework.exitMainThread();
    app.deinit();
    lf.framework.shutdown();
}
```

#### 5.13.5 填业务逻辑

**在生成的 `<Unit>_http_json_service_zig.zig` 里**，找到 `internal_call_<Api>` 桩：

```zig
pub fn internal_call_Add(a: i64, b: i64) i64 {
    _ = a;
    _ = b;
    // TODO: implement this stub.
    return 0;  // ← 替换这里
}
```

**推荐做法**：新建 `calculator_impl.zig`，桩里 `return calculator_impl.add(a, b)`。

#### 5.13.6 关闭

```zig
lf.framework.exitMainThread();
app.deinit();
lf.framework.shutdown();
```

#### 5.13.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `framework.init failed` | LingoFuse64.dll 缺失 | 复制到 `zig_service_test/` |
| `prepareService failed` | 端点已被占用 | 换端点或杀旧进程 |
| `std.array_list.Managed` 编译错误 | Zig 版本过旧 | 用 Zig 0.13+ |

---

### 5.14 Erlang

#### 5.14.1 产物

```
<Unit>_http_json_service.erl
```

#### 5.14.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse` Erlang binding | LingoFuse 发行版 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| Erlang/OTP 25+ | — | ✅ |

#### 5.14.3 平台

- **运行时**：Erlang/OTP 25+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.14.4 初始化

**生成的 `main/0` 已包含完整流程**：

```bash
escript <Unit>_http_json_service_main_test___.escript
```

**`main/0` 的核心流程**：

```erlang
main() ->
    ok = ensure_native(),
    AppName = app_name(),
    AppDesc = app_desc(),
    Endpoint = bridge_endpoint(),

    % 1. 创建 App
    {ok, App} = lingofuse:create_app(AppName, AppDesc),

    % 2. 配置
    ok = set_deployment_mode(),
    ok = do_reset_prepare(),

    % 3. 监听端点
    ok = do_prepare_service(Endpoint),

    % 4. 注册 API
    ok = register_all_apis(App, self()),

    % 5. 作为 client 连到同一端点
    ok = do_prepare_client(Endpoint, App),

    % 6. 启动 mesh
    ok = do_prepare_done(),

    % 7. 等待 App 可见
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

#### 5.14.5 填业务逻辑

**在生成的 `<Unit>_http_json_service.erl` 里**，找到 `internal_call_<Api>` 桩：

```erlang
%% HTTP/JSON API: Add.
internal_call_add(A, B) ->
    %% Suggested call: add(A, B).
    0.  %% ← 替换这里
```

**推荐做法**：新建 `calculator_impl.erl`，桩里 `calculator_impl:add(A, B)`。

#### 5.14.6 关闭

```erlang
cleanup(App) ->
    try lingofuse:exit_main_thread() catch _:_ -> ok end,
    try lingofuse:free_app(App)       catch _:_ -> ok end,
    try lingofuse:shutdown()           catch _:_ -> ok end,
    ok.
```

#### 5.14.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `no such file or directory: lingofuse_nif.dll` | NIF 缺失 | `setup_erlang_tests.ps1` 会复制 |
| `prepare_service_failed` | 端点已被占用 | 换端点或杀旧进程 |
| `app_not_registered` | App 未在 15 秒内可见 | 检查 `wait_self_registered` 超时 |

---

### 5.15 Fortran

#### 5.15.1 产物

```
<Unit>_http_json_service_mod.f90
```

#### 5.15.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lf_fortran_mod.f90` | LingoFuse 发行版 | ✅ |
| `lf_fortran.cpp` | LingoFuse 发行版 | ✅ |
| `LingoFuse.c` | LingoFuse 发行版 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| gfortran 9+ | — | ✅ |

#### 5.15.3 平台

- **编译器**：gfortran 9+ / ifort / flang。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.15.4 初始化

**生成的 `service_test.exe` 已包含完整流程**（由 `setup_fortran_tests.ps1` 构建）：

```bash
cd _build_fortran
./service_test.exe
```

**`service_test.exe` 的核心流程**：

```fortran
program service_main_test
  use iso_c_binding
  use lf_fortran_mod
  use <Unit>_http_json_service_mod
  implicit none

  type(c_ptr) :: app
  integer(c_int) :: rc, reg_rc

  ! 1. 配置
  call lf_reset_prepare()
  call lf_set_opt_wait_ready_ok(.false.)
  call lf_set_opt_overlap_connection(.true.)

  ! 2. 监听端点
  rc = lf_prepare_service('ipc:<Unit>_http_json', 'ipc:<Unit>_http_json')
  if (rc < 0) then
    write(*, '(A)') '[FATAL] lf_prepare_service failed'
    stop 1
  end if

  ! 3. 创建 App + 注册 API
  app = lf_app_create(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC)
  call register_all_http_json_apis(app, reg_rc)

  ! 4. 作为 client 连到同一端点
  rc = lf_prepare_client('ipc:<Unit>_http_json', app)
  if (rc < 0) then
    stop 1
  end if

  ! 5. 启动 mesh
  if (lf_prepare_done() /= 1_c_int) then
    stop 1
  end if

  write(*, '(A)') '[OK] Service ready. Press Enter to stop.'
  read (*, *)

  ! 6. 关闭
  call lf_exit_main_thread()
  call lf_app_destroy(app)
  call lf_shutdown()
end program
```

#### 5.15.5 填业务逻辑

**在生成的 `<Unit>_http_json_service_mod.f90` 里**，找到 `internal_call_<Api>` 函数：

```fortran
function internal_call_add(a, b) result(res)
  integer(c_int64_t), intent(in) :: a, b
  integer(c_int64_t) :: res

  ! TODO: replace the body below with a call to the real implementation.
  ! Example: res = add(a, b)
  res = 0_c_int64_t  ! ← 替换这里
end function
```

**推荐做法**：新建 `calculator_impl.f90`，`use calculator_impl`，`res = calculator_impl_add(a, b)`。

#### 5.15.6 关闭

```fortran
call lf_exit_main_thread()
call lf_app_destroy(app)
call lf_shutdown()
```

#### 5.15.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `gfortran: command not found` | 未装 | `apt install gfortran` 或 MinGW-w64 |
| `lf_prepare_service failed` | 端点已被占用 | 换端点或杀旧进程 |
| `LF_PrepareDone` 返回值非 1 | 同一进程已调用过 | 重启进程 |

---

### 5.16 Julia

#### 5.16.1 产物

```
<Unit>_http_json_service.jl
```

#### 5.16.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `LingoFuse` Julia 绑定 | LingoFuse 发行版 | ✅ |
| `JSON3` | Julia registry | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| Julia 1.9+ | — | ✅ |
| **`--threads=2` 或更多** | — | ✅ |

#### 5.16.3 平台

- **运行时**：Julia 1.9+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。**移动端因需要 LingoFuse 原生库而不可用**。

#### 5.16.4 初始化

**生成的 `run_service()` 已包含完整流程**：

```bash
julia --threads=2 <Unit>_http_json_service.jl
```

**`run_service()` 的核心流程**：

```julia
function run_service()::Int32
    # 1. 配置
    set_option("Wait_Connection_ReadyOk", "False")
    reset_prepare()

    # 2. 监听端点
    serv_ret = prepare_service(HTTP_SERVICE_ENDPOINT, HTTP_SERVICE_ENDPOINT)
    if serv_ret == -1
        println(stderr, "[ERROR] prepare_service failed")
        return Int32(1)
    end

    # 3. 创建 App + 注册 API
    app = App(HTTP_SERVICE_APP_NAME, HTTP_SERVICE_APP_DESC)
    try
        register_all_http_json_apis(app)

        # 4. 作为 client 连到同一端点
        client_ret = prepare_client(HTTP_SERVICE_ENDPOINT, app)
        if client_ret == -1
            println(stderr, "[ERROR] prepare_client failed")
            return Int32(1)
        end

        # 5. 启动 mesh
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

        # 6. 关闭
        exit_main_thread()
        println("[OK] Service stopped.")
    finally
        dispose!(app)
        shutdown()
    end
    return Int32(0)
end
```

#### 5.16.5 填业务逻辑

**在生成的 `<Unit>_http_json_service.jl` 里**，找到 `internal_call_<Api>` 桩：

```julia
function internal_call_Add(a::Int64, b::Int64)::Int64
    # TODO: implement this stub.
    # Suggested call: Add(a, b)
    return Int64(0)  # ← 替换这里
end
```

**推荐做法**：新建 `calculator_impl.jl`，桩里 `return calculator_impl.add(a, b)`。

#### 5.16.6 关闭

```julia
exit_main_thread()
dispose!(app)
shutdown()
```

#### 5.16.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `--threads=2 or more required` | 单线程 | 加 `--threads=2` |
| `prepare_client returned -1` | 端点已被占用 | 换端点或杀旧进程 |
| `prepare_done failed` | 同一进程已调用过 | 重启进程 |

---

### 5.17 R

#### 5.17.1 产物

```
<Unit>_http_json_service.R
<Unit>_http_json_service_impl.R
```

#### 5.17.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse` R 包 | LingoFuse 发行版 | ✅ |
| `jsonlite` | CRAN | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| R 4.0+ | — | ✅ |

#### 5.17.3 平台

- **运行时**：R 4.0+。
- **OS**：Windows（x64）、Linux（x64/arm64）、macOS（x64/arm64）。

#### 5.17.4 初始化

**生成的 `.R` 脚本已包含完整流程**：

```bash
Rscript <Unit>_http_json_service.R
```

**`_main` 的核心流程**：

```r
.main <- function() {
    cat("=== ", APP_NAME, " native R LingoFuse service ===\n", sep = "")

    # 1. 加载用户实现
    .load_impl()

    # 2. 加载 LingoFuse 原生库
    rt <- .resolve_runtime_dir()
    lingofuse::lf_load(runtime_dir = rt)

    # 3. 创建 App
    app <- lingofuse::lf_create_app(APP_NAME, APP_DESC)

    # 4. 注册 API
    for (spec in api_specs) {
        cb <- .make_cb(spec$name, spec$params, spec$description)
        ok <- lingofuse::lf_register_call(app, spec$name, spec$description, cb)
    }

    # 5. 监听端点 + 作为 client 连到同一端点
    svc_tag <- lingofuse::lf_prepare_service(LF_ENDPOINT, LF_ENDPOINT)
    cli_tag <- lingofuse::lf_prepare_client(LF_ENDPOINT, app)
    rc <- lingofuse::lf_prepare_done()

    # 6. 等待 service.exit 哨兵文件
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

    # 7. 关闭
    lingofuse::lf_exit_main_thread()
    lingofuse::lf_free_app(app)
    lingofuse::lf_shutdown()
    quit(save = "no", status = 0)
}
```

#### 5.17.5 填业务逻辑

**在生成的 `<Unit>_http_json_service_impl.R` 里**，找到每个 `internal_call_<api>` 函数：

```r
add <- function(a, b) {
    # TODO: implement.
    return(0)  # ← 替换这里
}
```

**推荐做法**：把业务逻辑放在独立的 `.R` 文件里，`source()` 进来，`impl.R` 只做转发。

#### 5.17.6 关闭

```r
lingofuse::lf_exit_main_thread()
lingofuse::lf_free_app(app)
lingofuse::lf_shutdown()
quit(save = "no", status = 0)
```

#### 5.17.7 停止 R 服务的推荐方式

**不要用 Ctrl+C**。用一个独立的 PowerShell 窗口写入哨兵文件：

```powershell
'' > "<脚本目录>\service.exit"
```

服务会在约 100ms 内检测到，按顺序执行 `exit_main_thread` → `free_app` → `shutdown`，然后退出。

#### 5.17.8 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Package 'lingofuse' is required` | 未装 | `setup_r_tests.ps1 -InstallMissing` |
| `Cannot locate the LingoFuse runtime` | 未设 `LINGOFUSE_RUNTIME` | 设环境变量 |
| `lf_prepare_service failed` | 端点已被占用 | 换端点或杀旧进程 |

---

## 6. 无 Service 侧的语言

以下三种语言**没有 Service 侧**，只能做 Call：

| 语言 | 原因 | 替代方案 |
|------|------|----------|
| **JavaScript（浏览器）** | 浏览器无法加载 LingoFuse 原生库 | 用 Node.js / TypeScript 做 Service |
| **PHP** | PHP 无 LingoFuse 原生库支持 | 用 Python / Ruby / Java 做 Service |
| **Delphi** | Delphi 的 `System.Net.HttpClient` 是纯 HTTP 客户端 | 用 Pascal（FPC）做 Service |

**这意味着**：如果你需要在这三种语言里"提供接口"，必须把 Service 部署在其他语言（Python / Pascal / C++ / ...）上，让这三种语言作为 Call 通过桥接访问。

**架构示例**：

```
浏览器 JS（Call）──HTTP──▶ bridge.py ──LF_Call──▶ Python Service
```

**不是**：

```
浏览器 JS（Service）  ← 不可能
```

---

## 7. 平台与操作系统支持矩阵

### 7.1 按语言

| 语言 | 编译器 / 运行时 | Windows | Linux | macOS | 其他 OS |
|------|----------------|:-------:|:-----:|:-----:|---------|
| Pascal | FPC 3.2+ / Delphi 11+ | ✅ | ✅ | ✅ | 受 LingoFuse 原生库限制 |
| Python | Python 3.8+ | ✅ | ✅ | ✅ | 受 LingoFuse Python 包限制 |
| C++ | C++17 编译器 | ✅ | ✅ | ✅ | 受 LingoFuse 原生库限制 |
| C# | .NET 8.0+ | ✅ | ✅ | ✅ | 受 LingoFuse .NET 绑定限制 |
| Node.js | Node.js 18+ | ✅ | ✅ | ✅ | 受 LingoFuse 原生库限制 |
| TypeScript | Node.js 18+ | ✅ | ✅ | ✅ | 受 LingoFuse 原生库限制 |
| Rust | Rust 1.70+ | ✅ | ✅ | ✅ | 受 LingoFuse 原生库限制 |
| Go | Go 1.21+ + cgo | ✅ | ✅ | ✅ | 受 LingoFuse 原生库限制 |
| Java | JDK 11+ | ✅ | ✅ | ✅ | 受 LingoFuse Java 包限制 |
| Dart | Dart 3.0+ | ✅ | ✅ | ✅ | 受 LingoFuse Dart 包限制 |
| Swift | Swift 5.9+ | ✅ | ✅ | ✅ | 受 LingoFuse Swift 绑定限制 |
| Ruby | Ruby 2.7+ / 3.0+ | ✅ | ✅ | ✅ | 受 LingoFuse gem 限制 |
| Zig | Zig 0.13+ | ✅ | ✅ | ✅ | 受 LingoFuse 原生库限制 |
| Erlang | Erlang/OTP 25+ | ✅ | ✅ | ✅ | 受 LingoFuse Erlang binding 限制 |
| Fortran | gfortran 9+ | ✅ | ✅ | ✅ | 受 `lf_fortran.cpp` 限制 |
| Julia | Julia 1.9+ | ✅ | ✅ | ✅ | 受 LingoFuse Julia 绑定限制 |
| R | R 4.0+ | ✅ | ✅ | ✅ | 受 `lingofuse` R 包限制 |

### 7.2 按 OS

| 操作系统 | Service 支持 | 备注 |
|----------|:------------:|------|
| **Windows（x86 / x64 / arm64）** | ✅ 全部 17 种语言 | 需要 `LingoFuse64.dll` + `z_ipc_64.dll` |
| **Linux（x64 / arm64）** | ✅ 全部 17 种语言 | 需要 `liblingofuse.so` + `libz_ipc_64.so` |
| **macOS（x64 / arm64）** | ✅ 全部 17 种语言 | 需要 `liblingofuse.dylib` |
| **iOS / iPadOS** | ❌ | LingoFuse 原生库不支持 |
| **Android** | ❌ | LingoFuse 原生库不支持 |
| **WASM** | ❌ | LingoFuse 原生库不支持 |
| **FreeBSD / OpenBSD / NetBSD** | ❌ | LingoFuse 原生库不支持 |
| **嵌入式（ARM Cortex-M 等）** | ❌ | LingoFuse 原生库不支持 |

**关键结论**：**Service 只能部署在桌面 / 服务器平台**。移动端 / 嵌入式 / WASM 无法运行 Service。如果需要在移动端提供接口，**把 Service 部署在服务器上，让移动端作为 Call 通过桥接访问**。

### 7.3 与 Call 侧的平台对比

| 语言 | Service 平台 | Call 平台 |
|------|:------------:|:---------:|
| Python | 桌面 / 服务器 | 所有 Python 支持的平台（含移动端） |
| JavaScript | ❌ 无 Service | 所有现代浏览器 |
| Node.js | 桌面 / 服务器 | 所有 Node.js 支持的平台 |
| TypeScript | 桌面 / 服务器 | 同 Node.js / 浏览器 |
| Rust | 桌面 / 服务器 | 所有 Rust 支持的平台（含 WASM、嵌入式） |
| Go | 桌面 / 服务器（需 cgo） | 所有 Go 支持的平台（含 WASM、移动端） |
| Swift | 桌面 / 服务器（macOS / Linux） | 所有 Swift 支持的平台（含 iOS） |
| Dart | 桌面 / 服务器 | 所有 Dart 支持的平台（含移动端、Web） |
| ... | ... | ... |

**核心差异**：**Service 需要 LingoFuse 原生库，平台支持窄；Call 模式 A 不需要原生库，平台支持广**。

---

## 8. 横向对比速查表

### 8.1 接入方式

| 语言 | 需要 LingoFuse 原生库 | 需要 LingoFuse 语言绑定 | 初始化三件套 | 桩名 |
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

### 8.2 关闭顺序

| 语言 | 关闭顺序 |
|------|----------|
| Pascal | `LF_ExitMainThread` → `LF_FreeApp` → `LF_Shutdown` |
| Python | `LF_ExitMainThread` → `app.free()` → `LF_Shutdown` |
| C++ | `exitMainThread` → App 析构 → `shutdown` |
| C# | `NetworkEvents.Clear` → `ExitMainThread` → `app.Dispose` → `Shutdown` |
| Node.js | `exitMainThread` → `app.dispose()` → `shutdown` |
| TypeScript | `exitMainThread` → `app.dispose()` → `shutdown` |
| Rust | App Drop → 库 Drop |
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

### 8.3 端点与 App 名

| 概念 | 值 |
|------|-----|
| LingoFuse 端点 | `ipc:<UnitName>_http_json` |
| Service App 名 | `<UnitName>`（规范化后） |
| Service App 描述 | `HTTP/JSON service for <UnitName>` |
| Bridge App 名 | `__lf_http_bridge__` |
| Bridge API 名 | `__lf_outbound_post__` |

**Service 与 Bridge 必须使用同一个端点字符串**。

---

## 9. 常见集成问题

### 9.1 所有语言

| 症状 | 原因 | 修复 |
|------|------|------|
| `prepareService` / `prepare_service` 失败 | 端点已被占用 | 换端点或杀旧进程 |
| `prepareDone` / `prepare_done` 返回 0 | 同一进程已调用过 | 重启进程 |
| App 未在 mesh 上可见 | `Wait_Connection_ReadyOk` 未关 | 设置 `False` |
| Service 启动了但 Call 找不到 | Service 与 Bridge 端点不一致 | 统一端点字符串 |
| Service 启动了但 Call 仍 `Network error` | Bridge 未运行 | 启动 `bridge.py` |
| 关闭时崩溃 | 关闭顺序错误 | 按 `exitMainThread → FreeApp → shutdown` 顺序 |
| 进程不退出 | mesh 线程未 join | 加 `exitMainThread` 或 `exit!` |

### 9.2 Service 专属

| 症状 | 原因 | 修复 |
|------|------|------|
| `LF_LoadLibrary` 返回非 1 | LingoFuse 原生库缺失或架构不匹配 | 复制正确的 `LingoFuse64.dll` / `liblingofuse.so` |
| `no found app("<Unit>")`（bridge 报） | Service 未启动 | 启动 Service |
| `no found api("<Api>")`（bridge 报） | API 未注册 | 检查 `registerCall` 调用 |
| 桩函数未调用 | 用户没填 `internal_call_<Api>` | 填入业务逻辑 |
| 桩函数返回 0 | 默认桩就是返回 0 | 替换为真实逻辑 |

### 9.3 语言专属

| 语言 | 症状 | 原因 | 修复 |
|------|------|------|------|
| C# | `DllNotFoundException: LingoFuse64` | DLL 未复制 | 复制到 bin 目录 |
| C# | `Could not load type 'lingofuse.AppHandle'` | LingoFuse.dll 引用缺失 | `dotnet add reference` |
| Java | `UnsatisfiedLinkError: LingoFuse64` | 原生库缺失 | 加到 `-Djava.library.path` |
| Java | `ClassNotFoundException: jackson.databind.JsonNode` | Jackson 缺失 | 下载 `jackson-databind.jar` |
| Ruby | `cannot load such file -- lingofuse` | gem 未安装 | `gem install lingofuse` |
| Ruby | 进程不退出 | `NativeBridge.start` 线程未 join | 生成代码已用 `exit!` 强制退出 |
| Zig | `std.array_list.Managed` 编译错误 | Zig 版本过旧 | 用 Zig 0.13+ |
| Erlang | `no such file or directory: lingofuse_nif.dll` | NIF 缺失 | 复制到 `priv/` |
| Fortran | `undefined reference to 'lf_*'` | `lf_fortran.cpp` 未链接 | 用 `setup_fortran_tests.ps1` |
| Julia | `--threads=2 or more required` | 单线程 | 加 `--threads=2` |
| Julia | `prepare_client returned -1` | 端点已被占用 | 换端点或杀旧进程 |
| R | `The *_async variants require future::plan('sequential')` | future 计划不兼容 | `future::plan(future::sequential)` |
| R | 进程不退出 | `lf_poll` 循环未停 | 写 `service.exit` 哨兵文件 |
| Dart | `prepareDone returned false` | `Wait_Connection_ReadyOk` 未关 | 设置 `False` |
| Swift | `libraryLoadFailed` | `liblingofuse.dylib` 缺失 | 复制到可执行文件旁 |

### 9.4 Service 与 Bridge 的关系速查

| 问题 | 回答 |
|------|------|
| **Service 是否需要通过桥接？** | **不需要**。Service 是 mesh 节点，直接监听端点。 |
| **Service 是否需要 bridge 在运行？** | **不需要**。Service 可以单独启动（`--smoke` 模式）。 |
| **bridge 是否需要 Service 在运行？** | **需要**。bridge 是 client，它连到 mesh 端点，等 Service 注册 API。 |
| **Service 与 bridge 共享什么？** | **端点字符串**（`ipc:<UnitName>_http_json`）。 |
| **Service 先启动还是 bridge 先启动？** | **都可以**。bridge 是 client，可以晚于 Service 启动。 |
| **Service 停止后 bridge 还能用吗？** | **不能**。bridge 会报 `no found app("<Unit>")`。 |
| **bridge 停止后 Service 还能用吗？** | **Service 本身还能运行**，但**没有 Call 能访问它**（因为 Call 走 bridge）。 |
| **Service 能否不经过 mesh 直接 HTTP？** | **不能**。Service 侧必须通过 LingoFuse mesh 接收调用。 |

---

## 附录：一页速查表

| 语言 | 有 Service 侧 | 需要 LingoFuse 原生库 | 需要 LingoFuse 语言绑定 | 平台 |
|------|:------------:|:--------------------:|:----------------------:|------|
| Pascal | ✅ | ✅ | ✅ `lingofuse_import` | Win / Linux / macOS |
| Python | ✅ | ✅ | ✅ `lingofuse` Python 包 | Win / Linux / macOS |
| C++ | ✅ | ✅ | ✅ `LingoFuse.hpp` | Win / Linux / macOS |
| C# | ✅ | ✅ | ✅ `LingoFuse` .NET 绑定 | Win / Linux / macOS |
| **JavaScript** | ❌ | — | — | — |
| Node.js | ✅ | ✅ | ✅ `lingofuse-js` | Win / Linux / macOS |
| TypeScript | ✅ | ✅ | ✅ `lingofuse-ts` | Win / Linux / macOS |
| **PHP** | ❌ | — | — | — |
| Rust | ✅ | ✅ | ✅ `lingofuse` crate | Win / Linux / macOS |
| Go | ✅ | ✅ | ✅ `lingofuse` Go 包 | Win / Linux / macOS |
| Java | ✅ | ✅ | ✅ `lingofuse` Java 包 | Win / Linux / macOS |
| **Delphi** | ❌ | — | — | — |
| Dart | ✅ | ✅ | ✅ `lingofuse` Dart 包 | Win / Linux / macOS |
| Swift | ✅ | ✅ | ✅ `lingofuse` Swift 绑定 | macOS / Linux |
| Ruby | ✅ | ✅ | ✅ `lingofuse` gem | Win / Linux / macOS |
| Zig | ✅ | ✅ | ✅ `lingofuse` Zig 绑定 | Win / Linux / macOS |
| Erlang | ✅ | ✅ | ✅ `lingofuse` Erlang binding | Win / Linux / macOS |
| Fortran | ✅ | ✅ | ✅ `lf_fortran_mod` | Win / Linux / macOS |
| Julia | ✅ | ✅ | ✅ `LingoFuse` Julia 绑定 | Win / Linux / macOS |
| R | ✅ | ✅ | ✅ `lingofuse` R 包 | Win / Linux / macOS |

**Service 不需要通过桥接。** Service 是 LingoFuse mesh 的节点，直接监听端点，等待 bridge 把 HTTP 请求转成 LF_Call 送到它这里。**Service 是 bridge 的上游，不是下游**。

**Service 侧必须使用 LingoFuse 原生库与语言绑定。** 这是与 Call 侧最大的差异——Call 侧的模式 A 不需要原生库，而 Service 侧永远需要。

**Service 只能运行在桌面 / 服务器平台。** 移动端 / 嵌入式 / WASM 无法运行 Service。如果需要在移动端提供接口，把 Service 部署在服务器上，让移动端作为 Call 通过桥接访问。
