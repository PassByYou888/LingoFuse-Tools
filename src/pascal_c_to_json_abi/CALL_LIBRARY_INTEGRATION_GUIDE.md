# CALL 库接入方法指南

> 本文档给出 **每种目标语言** 对 **Call 库（调用侧）** 的接入方法。
>
> **Call 库是什么** — Call 库是"调用侧"产物，负责把本地函数调用转换为到 LingoFuse HTTP 桥接程序（`bridge.py` / `bridge.exe`）的请求，再把响应转换回本地类型的代码模块。
>
> **Call 库的三条通用前提**：
>
> 1. **桥接程序（`bridge.py` / `bridge.exe`）必须始终运行**。
> 2. **服务侧必须已启动并在线**（即目标 `<AppName>` 已加入 LingoFuse mesh）。
> 3. **桥接程序的 endpoint 必须与服务侧完全一致**（默认 `ipc:<UnitName>_http_json`）。
>
> **本文档的核心是"接入"** —— 即：在你的项目里如何引入、初始化、调用、配置、处理错误。**不覆盖"如何构建产物本身"**（构建步骤见 `BUILD_GUIDE.md`），也**不覆盖"如何运行测试驱动"**（运行步骤见 `HOW_TO_RUN_TESTS.md`）。
>
> **关于"是否需要桥接"** — **所有 20+ 种 Call 库都通过桥接程序访问服务**。没有例外。但**接入方式分为两大模式**：
>
> - **模式 A（直接 HTTP 模式）**：Call 库直接向桥接程序的 HTTP 端口 POST。**不需要 LingoFuse 原生库**。适用于 Python、JavaScript、Node.js、TypeScript、PHP、Rust、Go、Java、Delphi、Dart、Swift、Ruby、Erlang。
> - **模式 B（LingoFuse Mesh 模式）**：Call 库通过 LingoFuse C ABI 直接调用桥接程序的 `__lf_outbound_post__` API，桥接程序收到后再转发 HTTP。**需要 LingoFuse 原生库**。适用于 Pascal、C++、C#、Zig、Fortran、Julia、R。
>
> 两种模式最终都到桥接程序，但**依赖、初始化方式、平台支持范围**不同。详见第 2 章。

---

## 目录

1. [Call 库定位](#1-call-库定位)
2. [两种接入模式](#2-两种接入模式)
3. [通用前提：桥接程序必须始终运行](#3-通用前提桥接程序必须始终运行)
4. [模式 A 与模式 B 对比](#4-模式-a-与模式-b-对比)
5. [各语言接入详解](#5-各语言接入详解)
   - [5.1 Pascal（模式 B）](#51-pascal模式-b)
   - [5.2 Python（模式 A）](#52-python模式-a)
   - [5.3 C++（模式 B）](#53-c模式-b)
   - [5.4 C#（模式 B）](#54-c模式-b)
   - [5.5 JavaScript（模式 A）](#55-javascript模式-a)
   - [5.6 Node.js（模式 A）](#56-nodejs模式-a)
   - [5.7 TypeScript（模式 A）](#57-typescript模式-a)
   - [5.8 PHP（模式 A）](#58-php模式-a)
   - [5.9 Rust（模式 A）](#59-rust模式-a)
   - [5.10 Go（模式 A）](#510-go模式-a)
   - [5.11 Java（模式 A）](#511-java模式-a)
   - [5.12 Delphi（模式 A）](#512-delphi模式-a)
   - [5.13 Dart（模式 A）](#513-dart模式-a)
   - [5.14 Swift（模式 A）](#514-swift模式-a)
   - [5.15 Ruby（模式 A）](#515-ruby模式-a)
   - [5.16 Zig（模式 B）](#516-zig模式-b)
   - [5.17 Erlang（模式 A）](#517-erlang模式-a)
   - [5.18 Fortran（模式 B）](#518-fortran模式-b)
   - [5.19 Julia（模式 B）](#519-julia模式-b)
   - [5.20 R（模式 B）](#520-r模式-b)
6. [平台与操作系统支持矩阵](#6-平台与操作系统支持矩阵)
7. [横向对比速查表](#7-横向对比速查表)
8. [常见集成问题](#8-常见集成问题)

---

## 1. Call 库定位

### 1.1 Call 库 = 调用侧

一个完整的接口对由 **Service（服务侧）** 与 **Call（调用侧）** 组成：

| 侧 | 职责 | 是否走桥接程序 |
|----|------|:--------------:|
| **Service** | 把函数注册为 LingoFuse Call API，接收 JSON 请求并返回 JSON 响应 | ❌（服务本身不走桥接） |
| **Call** | 把本地函数调用转为到桥接程序的请求，再把响应转回本地类型 | ✅ **必须** |

### 1.2 Call 库的产物命名

```
<UnitName>_http_json_call_<lang_suffix>.<ext>
```

| 语言 | Call 库文件名 |
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

### 1.3 Call 库暴露的公共接口

每种语言的 Call 库都暴露：

- **每个支持的 API** 的一个类型化函数（同步）。
- **每个支持的 API** 的一个类型化函数（异步，如果语言支持）。
- **一个配置对象**（Base URL、超时、桥接 App 名等）。
- **一个错误类型**（`HTTPCallError` / `EHTTPCallError` / `LFHttpCallError` / `HttpJsonCallError` / `HttpCallError` / `HTTPCallException` 等）。

**同步 vs 异步的支持情况**见第 7 章。

---

## 2. 两种接入模式

### 2.1 模式 A — 直接 HTTP 模式

**Call 库直接向桥接程序的 HTTP 端口 POST。**

```
Call 库  ──HTTP POST──▶  bridge.py :8081  ──LF_Call──▶  Service
Call 库  ◀─HTTP 响应──    bridge.py :8081  ◀─LF 返回───  Service
```

**特点**：

- **不需要 LingoFuse 原生库**（`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`）。
- **不需要 LingoFuse 端点**。
- **不需要 LingoFuse 客户端初始化**。
- 只需要 `HTTP_CALL_BASE_URL` 指向 `http://127.0.0.1:8081/<UnitName>`。
- 依赖是语言自身的 HTTP 客户端 + JSON 库。
- **平台支持范围 = 语言自身的支持范围**。

**采用模式 A 的语言**：

| # | 语言 | HTTP 客户端 | JSON 库 |
|:-:|------|-------------|---------|
| 1 | Python | `requests` | 内置 `json` |
| 2 | JavaScript（浏览器） | 内置 `fetch` | 内置 `JSON` |
| 3 | Node.js | 内置 `fetch`（Node 18+） | 内置 `JSON` |
| 4 | TypeScript | 内置 `fetch` | 内置 `JSON` |
| 5 | PHP | `curl_*` / `fopen` | 内置 `json_encode` / `json_decode` |
| 6 | Rust | `ureq`（同步）/ `reqwest`（异步） | `serde_json` |
| 7 | Go | `net/http` | 内置 `encoding/json` |
| 8 | Java | `java.net.http.HttpClient` | Jackson `ObjectMapper` |
| 9 | Delphi | `System.Net.HttpClient` | `System.JSON` |
| 10 | Dart | `package:http` | 内置 `dart:convert` |
| 11 | Swift | `URLSession` | `JSONSerialization` |
| 12 | Ruby | `net/http` | 内置 `json` |
| 13 | Erlang | `httpc` | `json` Erlang 库 |

### 2.2 模式 B — LingoFuse Mesh 模式

**Call 库通过 LingoFuse C ABI 直接调用桥接程序的 `__lf_outbound_post__` API，桥接程序收到后再转发 HTTP。**

```
Call 库  ──LF_Call──▶  bridge.py  ──HTTP POST──▶  Service
Call 库  ◀─LF 返回──   bridge.py  ◀─HTTP 响应───  Service
```

**特点**：

- **需要 LingoFuse 原生库**（`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`）与 `z_ipc_*`。
- **需要 LingoFuse 端点**（默认 `ipc:<UnitName>_http_json`）。
- **需要 LingoFuse 客户端初始化**：
  - `LF_LoadLibrary` / 语言特定的 `init`。
  - `LF_PrepareClientEx` / `prepareClient` / `prepare_client`。
  - `LF_PrepareDone` / `prepareDone` / `prepare_done`。
- 通过 `__lf_http_bridge__.__lf_outbound_post__` 到达桥接程序。
- **平台支持范围 = LingoFuse 原生库的支持范围**。

**采用模式 B 的语言**：

| # | 语言 | 接入入口 | 依赖 |
|:-:|------|----------|------|
| 1 | Pascal | `LFHttpPost` / `LF_Async_CallEx`（来自 `lf_http_bridge_client`） | `lingofuse_import`、`lf_http_bridge_client` |
| 2 | C++ | `lingofuse::bridge::httpCall` / `lingofuse::callAsync`（来自 `lf_http_bridge_client.hpp`） | `LingoFuse.hpp`、`lf_http_bridge_client.hpp`、`json.hpp` |
| 3 | C# | `Framework.Call` / `Async.Call`（来自 `LingoFuse` .NET 绑定） | `LingoFuse` .NET 绑定 |
| 4 | Zig | `lf.framework.call` / `lf.async_call.callAsync`（来自 `lingofuse` Zig 绑定） | `lingofuse` Zig 绑定 |
| 5 | Fortran | `lf_call` / `lf_async_call`（来自 `lf_fortran_mod`） | `lf_fortran_mod.f90`、`lf_fortran.cpp` |
| 6 | Julia | `lingofuse.call` / `lingofuse.future`（来自 `LingoFuse` Julia 绑定） | `LingoFuse`、`JSON3` |
| 7 | R | `lingofuse::lf_call`（来自 `lingofuse` R 包） | `lingofuse`、`jsonlite`、`future`（仅异步） |

### 2.3 为什么有两种模式

- **模式 A**：纯粹为了**最小依赖**。调用方语言有成熟的 HTTP 客户端，直接 HTTP 是最简单、最可移植的接入方式。**新语言优先走模式 A**。
- **模式 B**：因为某些语言（或某些场景）**必须使用 LingoFuse 的 mesh 路由能力**（例如需要跨网络、需要 App 名 / UID / P2PName 路由），或者因为语言生态里没有稳定的 HTTP 客户端，或者因为既有用户已经依赖 LingoFuse 的 C ABI。

**两种模式的最终效果相同**：服务侧收到的都是同一个 JSON 请求。

---

## 3. 通用前提：桥接程序必须始终运行

**这是所有 20+ 种 Call 库的共同前提。** 见 `USER_GUIDE.md` 第 2 章。

**速记**：

```bash
python3 bridge.py --endpoint ipc:<UnitName>_http_json --port 8081 --no-precheck
```

| 参数 | 说明 |
|------|------|
| `--endpoint` | 与服务侧**完全相同**的 LingoFuse 端点 |
| `--port` | 桥接程序的 HTTP 监听端口。默认 8081 |
| `--no-precheck` | 跳过启动时的 API 预检查。**强烈推荐** |
| `--bridge-app` | 覆盖桥接默认 App 名（默认 `__lf_http_bridge__`） |
| `--bridge-api` | 覆盖桥接默认 API 名（默认 `__lf_outbound_post__`） |

**三进程布局**：

```
终端 1（服务）：  启动生成的服务
终端 2（桥接）：  python3 bridge.py --endpoint ipc:<UnitName>_http_json --port 8081
终端 3（调用）：  启动你的 Call 库集成代码
```

**如果桥接程序没运行**，所有 Call 库都会立刻失败：

| 模式 | 典型错误 |
|------|----------|
| 模式 A | `Connection refused` / `Network error` / `HTTPCallError` |
| 模式 B | `LF_PrepareClient returned -1` / `LF_Async_CallEx failed` / `no found app("__lf_http_bridge__")` |

---

## 4. 模式 A 与模式 B 对比

| 维度 | 模式 A（直接 HTTP） | 模式 B（LingoFuse Mesh） |
|------|:------------------:|:-----------------------:|
| **需要桥接程序** | ✅ 必须 | ✅ 必须 |
| **需要 LingoFuse 原生库** | ❌ 不需要 | ✅ 必须 |
| **需要 LingoFuse 端点** | ❌ 不需要 | ✅ 必须 |
| **需要 LingoFuse 初始化** | ❌ 不需要 | ✅ 必须（init / prepareClient / prepareDone） |
| **通信协议** | HTTP POST | LingoFuse C ABI → bridge 的 `__lf_outbound_post__` |
| **依赖** | 语言 HTTP 客户端 + JSON 库 | LingoFuse C ABI + LingoFuse 绑定 |
| **平台支持** | 语言自身支持范围 | LingoFuse 原生库支持范围 |
| **跨网络调用** | 需要 bridge 暴露到公网 | 通过 LingoFuse mesh（App 名 / UID / P2PName 路由） |
| **适用语言** | Python / JS / Node.js / TS / PHP / Rust / Go / Java / Delphi / Dart / Swift / Ruby / Erlang | Pascal / C++ / C# / Zig / Fortran / Julia / R |
| **配置入口** | `HTTP_CALL_BASE_URL`（指向 `http://127.0.0.1:8081/<Unit>`） | `HTTP_CALL_BASE_URL` + `HTTP_BRIDGE_APP_NAME` + `HTTP_BRIDGE_API_NAME` + `LF_CLIENT_ENDPOINT` |
| **典型错误** | `Connection refused` | `LF_PrepareClient returned -1` |
| **启动顺序** | 服务 → 桥接 → 调用侧 | 服务 → 桥接 → 调用侧（且调用侧需 LingoFuse 初始化） |

**给集成者的建议**：

- 如果你的语言在模式 A 列表里，**优先用模式 A**——依赖更少、平台更广、接入更简单。
- 如果你的语言在模式 B 列表里（或你需要 LingoFuse 的 mesh 路由能力），用模式 B。
- 模式 A 与模式 B 可以**混用**（一个项目里不同语言用不同模式），只要都指向同一个桥接程序。

---

## 5. 各语言接入详解

### 5.1 Pascal（模式 B）

#### 5.1.1 产物

```
<Unit>_http_json_call_unit.pas
```

#### 5.1.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `lingofuse_import.pas` | LingoFuse 发行版 | ✅ |
| `lf_http_bridge_client.pas` | LingoFuse 发行版 | ✅ |
| `Z.Core`、`Z.PascalStrings`、`Z.UPascalStrings`、`Z.UnicodeMixedLib`、`Z.Json` | Z 框架 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` / `libz_ipc_64.so` | LingoFuse 发行版 | ✅（运行时） |

#### 5.1.3 平台

- **编译器**：FPC 3.2+ / Delphi 11+。
- **操作系统**：Windows（32/64 位）、Linux（x86_64 / aarch64）、macOS（x86_64 / arm64）。**受 LingoFuse 原生库支持范围限制**。

#### 5.1.4 初始化

```pascal
uses
  lingofuse_import,
  <Unit>_http_json_call_unit;

var
  App: TAppHnd___;
begin
  // 1. 加载 LingoFuse 原生库（若未自动加载）
  //    LF_LoadLibrary 会在第一次 LF_* 调用时自动触发，但显式调用更安全。
  if LF_LoadLibrary() <> 1 then
  begin
    WriteLn('Failed to load LingoFuse');
    Halt(1);
  end;

  // 2. 连接到与 bridge.py 相同的 LingoFuse 端点
  LF_PrepareClientEx('ipc:<Unit>_http_json', nil);
  if LF_PrepareDone() <> 1 then
  begin
    WriteLn('LingoFuse prepare failed');
    Halt(1);
  end;

  // 3. 配置 Base URL（默认已是 http://127.0.0.1:8081/<Unit>）
  HTTP_CALL_BASE_URL := 'http://127.0.0.1:8081/<Unit>';
end;
```

#### 5.1.5 同步调用

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

#### 5.1.6 异步调用

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

**注意**：异步回调在**工作线程**上执行。更新 UI 需自行 `TThread.Queue(nil, ...)`。

#### 5.1.7 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `HTTP_CALL_BASE_URL` | `string` | `'http://127.0.0.1:8081/<Unit>'` | 桥接程序的 HTTP 前缀 |
| `HTTP_CALL_TIMEOUT_MS` | `Integer` | `30000` | 每次调用的超时（毫秒） |

#### 5.1.8 错误处理

- **异常类型**：`EHTTPCallError`。
- **字段**：`Code`（Integer）、`HttpStatus`（Integer）、`Message`（继承自 `Exception`）。

#### 5.1.9 关闭

```pascal
LF_ExitMainThread;
LF_Shutdown;
```

---

### 5.2 Python（模式 A）

#### 5.2.1 产物

```
<Unit>_http_json_call.py
```

#### 5.2.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `requests` | PyPI | ✅ |
| Python 3.8+ | — | ✅ |

**不需要** LingoFuse 原生库。

#### 5.2.3 平台

- **编译器 / 运行时**：Python 3.8+。
- **操作系统**：所有 Python + `requests` 支持的平台——Windows、Linux、macOS、FreeBSD、OpenBSD、NetBSD 等。

#### 5.2.4 初始化

```python
import <Unit>_http_json_call as api

# 设置 Base URL（默认已是 http://127.0.0.1:8081/<Unit>）
api.HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>"

# 设置超时（默认 30.0 秒）
api.HTTP_CALL_TIMEOUT = 30.0

# 开启 debug 日志（默认 False）
api.DEBUG_LOG = False
```

**不需要** LingoFuse 初始化。

#### 5.2.5 同步调用

```python
try:
    result = api.Add(1, 2)
    print(f"Add(1, 2) = {result}")
except api.HTTPCallError as e:
    print(f"Add failed: {e.message}, code={e.code}, http_status={e.http_status}")
```

#### 5.2.6 异步调用

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

#### 5.2.7 配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `HTTP_CALL_BASE_URL` | `'http://127.0.0.1:8081/<Unit>'` | 桥接程序的 HTTP 前缀 |
| `HTTP_CALL_TIMEOUT` | `30.0` | 超时（秒） |
| `DEBUG_LOG` | `False` | 是否打印请求 / 响应 |

#### 5.2.8 错误处理

- **异常类型**：`HTTPCallError`。
- **字段**：`.code`（int）、`.http_status`（int）、`.message`（str，继承自 `Exception`）。

#### 5.2.9 关闭

无（Python 的 `requests` 是无状态的；进程退出即释放）。

---

### 5.3 C++（模式 B）

#### 5.3.1 产物

```
<Unit>_http_json_call.hpp
<Unit>_http_json_call.cpp
```

#### 5.3.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| `LingoFuse.h`、`LingoFuse.c` | LingoFuse 发行版 | ✅ |
| `LingoFuse.hpp`、`lf_io.hpp` | LingoFuse 发行版 | ✅ |
| `lf_http_bridge_client.hpp` | LingoFuse 发行版 | ✅ |
| `json.hpp`（nlohmann） | 随 LingoFuse 发行版或单独获取 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |

#### 5.3.3 平台

- **编译器**：C++17（MSVC 2019+ / g++ 9+ / clang++ 10+）。
- **操作系统**：Windows、Linux、macOS。**受 LingoFuse C ABI 原生库支持范围限制**。

#### 5.3.4 初始化

```cpp
#include "LingoFuse.hpp"
#include "<Unit>_http_json_call.hpp"

int main() {
    // 1. 加载 LingoFuse 原生库（RAII）
    lingofuse::LibraryLoader loader;

    // 2. 连接到与 bridge.py 相同的端点
    lingofuse::resetPrepare();
    lingofuse::prepareClient("ipc:<Unit>_http_json", nullptr);
    if (lingofuse::prepareDone() != 1) {
        std::cerr << "LingoFuse init failed" << std::endl;
        return 1;
    }

    // 3. 配置 Base URL（默认已是 http://127.0.0.1:8081/<Unit>）
    <Unit>::HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>";

    // ... 调用 ...

    lingofuse::exitMainThread();
    lingofuse::shutdown();
    return 0;
}
```

#### 5.3.5 同步调用

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

#### 5.3.6 异步调用

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

**注意**：异步回调在**工作线程**上执行。回调内不要访问未加锁的共享状态。

#### 5.3.7 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `HTTP_CALL_BASE_URL` | `std::string` | `"http://127.0.0.1:8081/<Unit>"` | 桥接程序的 HTTP 前缀 |
| `HTTP_BRIDGE_APP_NAME` | `std::string` | `""`（即 `__lf_http_bridge__`） | 桥接 App 名 |
| `HTTP_BRIDGE_API_NAME` | `std::string` | `""`（即 `__lf_outbound_post__`） | 桥接 API 名 |
| `HTTP_CALL_TIMEOUT_MS` | `std::uint64_t` | `0`（默认 60000） | LingoFuse 往返超时 |
| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `double` | `0.0`（默认 25.0） | 外发 HTTP 超时 |

#### 5.3.8 错误处理

- **异常类型**：`<Unit>::HTTPCallError`（继承自 `std::runtime_error`）。
- **字段**：`.code`（int）、`.http_status`（int）、`.what()`（const char*）。

#### 5.3.9 关闭

```cpp
lingofuse::exitMainThread();
lingofuse::shutdown();
// LibraryLoader 析构时自动 LF_FreeLibrary
```

---

### 5.4 C#（模式 B）

#### 5.4.1 产物

```
<Unit>_http_json_call.cs
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
- **操作系统**：Windows、Linux、macOS。**受 LingoFuse .NET 绑定与原生库支持范围限制**。
- **.NET Framework 4.x**：**不支持**（生成代码使用 .NET 8+ 特性，如 `JsonDocument`、`System.Text.Json`）。

#### 5.4.4 初始化

```csharp
using LingoFuse;
using <Unit>_http_json_call;

// 1. 配置桥接参数（默认已指向 http://127.0.0.1:8081/<Unit>）
HttpJsonCallConfig.BaseUrl = "http://127.0.0.1:8081/<Unit>";
HttpJsonCallConfig.BridgeAppName = "__lf_http_bridge__";
HttpJsonCallConfig.BridgeApiName = "__lf_outbound_post__";
HttpJsonCallConfig.CallTimeoutMs = 60000;
HttpJsonCallConfig.HttpTimeoutSec = 25.0;

// 2. 连接 LingoFuse 端点
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

#### 5.4.5 同步调用

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

#### 5.4.6 异步调用

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

**注意**：`TaskCompletionSource` 的 `RunContinuationsAsynchronously` 是必需的，否则回调可能在 worker 线程上同步执行。

#### 5.4.7 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `HttpJsonCallConfig.BaseUrl` | `string` | `"http://127.0.0.1:8081/<Unit>"` | 桥接程序的 HTTP 前缀 |
| `HttpJsonCallConfig.BridgeAppName` | `string` | `"__lf_http_bridge__"` | 桥接 App 名 |
| `HttpJsonCallConfig.BridgeApiName` | `string` | `"__lf_outbound_post__"` | 桥接 API 名 |
| `HttpJsonCallConfig.CallTimeoutMs` | `ulong` | `60000` | LingoFuse 往返超时 |
| `HttpJsonCallConfig.HttpTimeoutSec` | `double` | `25.0` | 外发 HTTP 超时 |
| `HttpJsonCallConfig.DebugLog` | `bool` | `false` | 是否打印请求 URL |

#### 5.4.8 错误处理

- **异常类型**：`HTTPCallError`（继承自 `Exception`）。
- **字段**：`.Code`（int）、`.HttpStatus`（int）、`.Message`（string）。

#### 5.4.9 关闭

```csharp
try { NetworkEvents.Clear(); } catch { }
try { Framework.ExitMainThread(); } catch { }
try { Framework.Shutdown(); } catch { }
```

---

### 5.5 JavaScript（模式 A）

#### 5.5.1 产物

```
<Unit>_http_json_call.js
```

#### 5.5.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| 现代浏览器（Chrome / Edge / Firefox / Safari） | — | ✅ |
| 内置 `fetch`、`JSON` | — | ✅ |

**不需要** LingoFuse 原生库。

#### 5.5.3 平台

- **浏览器**：Chrome 57+、Edge 16+、Firefox 52+、Safari 11+（`fetch` 支持）。
- **操作系统**：任何有现代浏览器的 OS（Windows / macOS / Linux / ChromeOS / iOS / Android）。

#### 5.5.4 引入

**方式 A：`<script>` 标签**

```html
<script src="<Unit>_http_json_call.js"></script>
```

**方式 B：`import`（ES Module）**

生成的 `.js` 是 IIFE 形式，挂到 `window.<Unit>Api`，不是 ES Module。要作为模块使用，需自行改写。

#### 5.5.5 初始化

```javascript
// 全局对象已自动挂到 window.<Unit>Api
// 设置 Base URL
<Unit>Api.setBaseUrl("http://127.0.0.1:8081/<Unit>");

// 或直接读
console.log(<Unit>Api.getBaseUrl());
```

**不需要** LingoFuse 初始化。

#### 5.5.6 调用（只有异步）

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

#### 5.5.7 配置

| 配置项 | 方法 | 默认值 |
|--------|------|--------|
| Base URL | `<Unit>Api.setBaseUrl(url)` / `<Unit>Api.baseUrl` | `'http://127.0.0.1:8081/<Unit>'` |
| 错误类 | `<Unit>Api.Error` | `LFHttpCallError` |

**注意**：JavaScript 版**没有** `HTTP_CALL_TIMEOUT` 配置——`fetch` 用的是浏览器默认超时（通常是 300 秒）。

#### 5.5.8 错误处理

- **异常类型**：`<Unit>Api.Error`（即 `LFHttpCallError`）。
- **字段**：`.code`（number）、`.httpStatus`（number）、`.message`（string）。

#### 5.5.9 关闭

无（浏览器页面关闭即释放）。

---

### 5.6 Node.js（模式 A）

#### 5.6.1 产物

```
<Unit>_http_json_call_node.js
```

#### 5.6.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| Node.js 18+（`fetch` 内置） | — | ✅ |
| 内置 `fetch` | — | ✅ |

**不需要** LingoFuse 原生库。

#### 5.6.3 平台

- **运行时**：Node.js 18+。
- **操作系统**：Windows、Linux、macOS、FreeBSD、OpenBSD 等所有 Node.js 支持的平台。

#### 5.6.4 引入

```javascript
'use strict';

const api = require('./<Unit>_http_json_call_node.js');
```

#### 5.6.5 初始化

```javascript
api.HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>";
api.HTTP_CALL_TIMEOUT_MS = 30000;
api.DEBUG_LOG = false;

// 或通过环境变量
// process.env.LINGOFUSE_DEBUG = '1';
```

**不需要** LingoFuse 初始化。

#### 5.6.6 调用（只有异步）

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

#### 5.6.7 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `HTTP_CALL_BASE_URL` | `string` | `'http://127.0.0.1:8081/<Unit>'` | 桥接程序的 HTTP 前缀 |
| `HTTP_CALL_TIMEOUT_MS` | `number` | `30000` | 超时（毫秒），0 表示无超时 |
| `DEBUG_LOG` | `boolean` | `false`（或 `LINGOFUSE_DEBUG=1`） | 是否打印请求 / 响应 |

#### 5.6.8 错误处理

- **异常类型**：`api.HTTPCallError`（继承自 `Error`）。
- **字段**：`.code`（number）、`.httpStatus`（number）、`.message`（string）。

#### 5.6.9 关闭

无（Node.js 进程退出即释放）。

---

### 5.7 TypeScript（模式 A）

#### 5.7.1 产物

```
<Unit>_http_json_call_ts.ts
```

#### 5.7.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| TypeScript 5.0+ | npm | ✅ |
| 运行环境 Node 18+（通过 `tsx`）或现代浏览器 | — | ✅ |
| 内置 `fetch` | — | ✅ |

**不需要** LingoFuse 原生库。

#### 5.7.3 平台

- **运行时**：Node.js 18+（通过 `tsx` 直接运行 `.ts`）或编译为 JS 后在浏览器运行。
- **操作系统**：同运行环境。

#### 5.7.4 引入

```typescript
import * as api from "./<Unit>_http_json_call_ts";
```

#### 5.7.5 初始化

```typescript
api.HttpJsonCallConfig.baseUrl = "http://127.0.0.1:8081/<Unit>";
api.HttpJsonCallConfig.httpTimeoutMs = 30000;
api.HttpJsonCallConfig.debugLog = false;
```

**不需要** LingoFuse 初始化。

#### 5.7.6 调用（只有异步）

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

#### 5.7.7 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `HttpJsonCallConfig.baseUrl` | `string` | `'http://127.0.0.1:8081/<Unit>'` | 桥接程序的 HTTP 前缀 |
| `HttpJsonCallConfig.httpTimeoutMs` | `number` | `30000` | 超时（毫秒） |
| `HttpJsonCallConfig.debugLog` | `boolean` | `false` | 是否打印请求 / 响应 |

**每个 API 还接受可选的 `HttpJsonCallOptions`**：

```typescript
await api.Add(1, 2, { timeoutMs: 5000 });
```

#### 5.7.8 错误处理

- **异常类型**：`api.HttpJsonCallError`（继承自 `Error`）。
- **字段**：`.code`（number）、`.httpStatus`（number）、`.message`（string）。

#### 5.7.9 关闭

无（进程退出即释放）。

---

### 5.8 PHP（模式 A）

#### 5.8.1 产物

```
<Unit>_http_json_call_php.php
```

#### 5.8.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| PHP 7.4+ | — | ✅ |
| `curl` 扩展（首选） | — | 推荐 |
| `allow_url_fopen=On`（备选） | — | 备选 |
| 内置 `json_encode` / `json_decode` | — | ✅ |

**不需要** LingoFuse 原生库。

#### 5.8.3 平台

- **运行时**：PHP 7.4+。
- **操作系统**：Windows、Linux、macOS、FreeBSD 等所有 PHP 支持的平台。

#### 5.8.4 引入

```php
require_once __DIR__ . '/<Unit>_http_json_call_php.php';

use <SafeNamespace>\HttpJsonCallApi;
use <SafeNamespace>\HttpJsonCallConfig;
use <SafeNamespace>\HttpJsonCallError;
```

**`<SafeNamespace>`** 是规范化后的单元名（例如 `unit Calculator;` → `Calculator`）。

#### 5.8.5 初始化

```php
HttpJsonCallConfig::$baseUrl = "http://127.0.0.1:8081/<Unit>";
HttpJsonCallConfig::$httpTimeoutSec = 30;
HttpJsonCallConfig::$debugLog = false;
```

**不需要** LingoFuse 初始化。

#### 5.8.6 调用（同步）

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

**PHP 版只有同步调用**（没有 `_async` 变体）。

#### 5.8.7 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `HttpJsonCallConfig::$baseUrl` | `string` | `'http://127.0.0.1:8081/<Unit>'` | 桥接程序的 HTTP 前缀 |
| `HttpJsonCallConfig::$httpTimeoutSec` | `int` | `30` | 超时（秒） |
| `HttpJsonCallConfig::$debugLog` | `bool` | `false` | 是否打印请求 / 响应 |

**每个 API 还接受可选的 `$options` 参数**：

```php
HttpJsonCallApi::Add(1, 2, ['timeoutSec' => 5]);
```

#### 5.8.8 错误处理

- **异常类型**：`HttpJsonCallError`（继承自 `\RuntimeException`）。
- **字段**：`.getCode()`（int）、`.httpStatus`（int）、`.getMessage()`（string）。

#### 5.8.9 关闭

无（PHP 的 `curl` 在每次请求后自动释放）。

---

### 5.9 Rust（模式 A）

#### 5.9.1 产物

```
<Unit>_http_json_call_rs.rs
```

#### 5.9.2 依赖

**`Cargo.toml`**：

```toml
[dependencies]
ureq = "2"                                    # 同步
reqwest = { version = "0.12", features = ["json"] }  # 异步
tokio = { version = "1", features = ["rt", "rt-multi-thread", "macros"] }
serde_json = "1"
```

**不需要** LingoFuse 原生库。

#### 5.9.3 平台

- **编译器 / 运行时**：Rust 1.70+。
- **操作系统**：Windows、Linux、macOS、FreeBSD、各种嵌入式平台——**所有 Rust 支持的平台**。

#### 5.9.4 引入

**方式 A：crate root（`src/main.rs` 或 `src/lib.rs`）**

```rust
mod <unit_snake_case>_http_json_call;  // 文件名
use <unit_snake_case>_http_json_call as api;
```

**方式 B：`#[path]` 子模块**

```rust
#[path = "<Unit>_http_json_call_rs.rs"]
mod api;
```

#### 5.9.5 初始化

```rust
api::set_base_url("http://127.0.0.1:8081/<Unit>");
api::set_timeout_secs(30);
api::set_debug_log(false);
```

**不需要** LingoFuse 初始化。

#### 5.9.6 同步调用

```rust
match api::Add(1, 2) {
    Ok(sum) => println!("Add(1, 2) = {}", sum),
    Err(e) => eprintln!("Add failed: {} (code={}, http={})",
                        e, e.code, e.http_status),
}
```

#### 5.9.7 异步调用

```rust
#[tokio::main]
async fn main() {
    match api::Add_async(1, 2).await {
        Ok(sum) => println!("Add(1, 2) = {}", sum),
        Err(e) => eprintln!("Add failed: {}", e),
    }
}
```

**必须**在 `#[tokio::main]` 或手动构建的 `tokio::runtime::Runtime` 内运行。

#### 5.9.8 配置

| 配置项 | 函数 | 默认值 |
|--------|------|--------|
| Base URL | `set_base_url(&str)` / `get_base_url() -> String` | `"http://127.0.0.1:8081/<Unit>"` |
| 超时（秒） | `set_timeout_secs(u64)` / `get_timeout_secs() -> u64` | `30`（0 表示无超时） |
| Debug 日志 | `set_debug_log(bool)` / `get_debug_log() -> bool` | `false` |

#### 5.9.9 错误处理

- **错误类型**：`api::HttpCallError`（实现了 `std::error::Error` + `std::fmt::Display`）。
- **字段**：`.code`（i32）、`.http_status`（i32）、`.message`（String）。

#### 5.9.10 关闭

无（Rust 的 `ureq` / `reqwest` 在 drop 时自动释放）。

---

### 5.10 Go（模式 A）

#### 5.10.1 产物

```
<Unit>_http_json_call_go.go
```

#### 5.10.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| Go 1.21+ | — | ✅ |
| 标准库（`net/http`、`encoding/json`、`context`） | — | ✅ |

**不需要** LingoFuse 原生库。

#### 5.10.3 平台

- **运行时**：Go 1.21+。
- **操作系统**：Windows、Linux、macOS、FreeBSD、OpenBSD、NetBSD、Plan 9、Android、iOS、WASM——**所有 Go 支持的平台**。

#### 5.10.4 引入

```go
import (
    "github.com/yourorg/yourmodule/<unit>_http_json_call_go"
)
```

或同包内直接使用。

#### 5.10.5 初始化

```go
call.SetBaseURL("http://127.0.0.1:8081/<Unit>")
call.SetTimeout(30 * time.Second)
call.SetDebugLog(false)
```

**不需要** LingoFuse 初始化。

#### 5.10.6 同步调用

```go
sum, err := call.Add(1, 2)
if err != nil {
    log.Printf("Add failed: %v", err)
} else {
    log.Printf("Add(1, 2) = %d", sum)
}
```

**无返回值的过程（procedure）**：

```go
err := call.Log("hello")
if err != nil {
    log.Printf("Log failed: %v", err)
}
```

#### 5.10.7 异步调用（channel 风格）

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

#### 5.10.8 配置

| 配置项 | 变量 / 函数 | 默认值 |
|--------|------------|--------|
| Base URL | `HTTPCallBaseURL` / `SetBaseURL(string)` | `DefaultBaseURL` |
| 超时 | `HTTPCallTimeout` / `SetTimeout(time.Duration)` | `30 * time.Second`（0 表示无超时） |
| Debug 日志 | `DebugLog` / `SetDebugLog(bool)` | `false` |

#### 5.10.9 错误处理

- **错误类型**：`*call.HTTPCallError`（实现了 `error` 接口）。
- **字段**：`.Message`（string）、`.Code`（int）、`.HTTPStatus`（int）。

#### 5.10.10 关闭

无（Go 的 `http.Client` 是零值可用的；进程退出即释放）。

---

### 5.11 Java（模式 A）

#### 5.11.1 产物

```
HttpJsonClient.java
```

#### 5.11.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| JDK 11+ | — | ✅ |
| `jackson-databind.jar` | Maven Central / 手动 | ✅ |
| 内置 `java.net.http.HttpClient` | — | ✅ |

**不需要** LingoFuse 原生库。

#### 5.11.3 平台

- **运行时**：JDK 11+（推荐 17+）。
- **操作系统**：Windows、Linux、macOS、Solaris、AIX——**所有 JDK 支持的平台**。

#### 5.11.4 引入

```java
import <package>.HttpJsonClient;
import <package>.HttpJsonClient.HTTPCallException;
```

**`<package>`** 是生成代码所在的 Java 包（默认无包名，需自行 `package` 声明或在使用方的包内）。

#### 5.11.5 初始化

```java
HttpJsonClient.HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>";
HttpJsonClient.HTTP_CALL_TIMEOUT = java.time.Duration.ofSeconds(30);
```

**不需要** LingoFuse 初始化。

#### 5.11.6 调用（只有同步）

```java
try {
    long sum = HttpJsonClient.Add(1, 2);
    System.out.println("Add(1, 2) = " + sum);
} catch (HttpJsonClient.HTTPCallException e) {
    System.err.println("Add failed: " + e.getMessage()
        + " (code=" + e.code + ", http=" + e.httpStatus + ")");
}
```

**Java 版只有同步调用**（没有 `_async` 变体）。

#### 5.11.7 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `HTTP_CALL_BASE_URL` | `String` | `"http://127.0.0.1:8081/<Unit>"` | 桥接程序的 HTTP 前缀 |
| `HTTP_CALL_TIMEOUT` | `Duration` | `Duration.ofSeconds(30)` | 超时 |

#### 5.11.8 错误处理

- **异常类型**：`HttpJsonClient.HTTPCallException`（继承自 `RuntimeException`）。
- **字段**：`.code`（int）、`.httpStatus`（int）、`.getMessage()`（String）。

#### 5.11.9 关闭

无（Java 的 `HttpClient` 是进程级单例）。

---

### 5.12 Delphi（模式 A）

#### 5.12.1 产物

```
<Unit>_http_json_call_delphi.pas
```

#### 5.12.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| Delphi 10.3+ | — | ✅ |
| `System.Net.HttpClient`、`System.JSON`、`System.Classes`、`System.Generics.Collections`、`System.Net.URLClient` | — | ✅ |

**不需要** LingoFuse 原生库。

#### 5.12.3 平台

- **编译器**：Delphi 10.3+。
- **操作系统**：Windows、macOS、iOS、Android、Linux——**受 Delphi 版本限制**。Delphi 10.3 支持 Windows 32/64 位、macOS 64 位、iOS、Android、Linux 64 位。

#### 5.12.4 引入

```pascal
uses
  <Unit>_http_json_call_delphi;
```

#### 5.12.5 初始化

```pascal
HTTP_CALL_BASE_URL := 'http://127.0.0.1:8081/<Unit>';
HTTP_CALL_TIMEOUT_MS := 30000;
```

**不需要** LingoFuse 初始化。

#### 5.12.6 同步调用

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

#### 5.12.7 异步调用

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

**注意**：异步回调在**工作线程**上执行。更新 UI 需 `TThread.Queue`。

#### 5.12.8 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `HTTP_CALL_BASE_URL` | `string` | `'http://127.0.0.1:8081/<Unit>'` | 桥接程序的 HTTP 前缀 |
| `HTTP_CALL_TIMEOUT_MS` | `Integer` | `30000` | 超时（毫秒），0 表示无超时 |

#### 5.12.9 错误处理

- **异常类型**：`EHTTPCallError`（继承自 `Exception`）。
- **字段**：`.Code`（Integer）、`.HttpStatus`（Integer）、`.Message`（string）。

#### 5.12.10 关闭

无（Delphi 的 `THTTPClient` 在每次调用后释放）。

---

### 5.13 Dart（模式 A）

#### 5.13.1 产物

```
<Unit>_http_json_call.dart
```

#### 5.13.2 依赖

**`pubspec.yaml`**：

```yaml
dependencies:
  http: ^1.0.0
```

**不需要** LingoFuse 原生库。

#### 5.13.3 平台

- **运行时**：Dart 3.0+。
- **操作系统**：Windows、Linux、macOS、iOS、Android、Web（通过 Flutter 或 Dart Web）——**所有 Dart 支持的平台**。

#### 5.13.4 引入

```dart
import 'package:your_package/<Unit>_http_json_call.dart' as api;
```

或同目录下：

```dart
import '<Unit>_http_json_call.dart' as api;
```

#### 5.13.5 初始化

```dart
api.setBaseUrl('http://127.0.0.1:8081/<Unit>');
api.HTTP_CALL_TIMEOUT = const Duration(seconds: 30);
api.DEBUG_LOG = false;
```

**不需要** LingoFuse 初始化。

#### 5.13.6 调用（只有异步）

```dart
try {
    final sum = await api.Add(1, 2);
    print('Add(1, 2) = $sum');
} on api.HttpCallError catch (e) {
    print('Add failed: ${e.message}, code=${e.code}, http=${e.httpStatus}');
}
```

#### 5.13.7 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| Base URL | `setBaseUrl(url)` / `getBaseUrl()` / `DEFAULT_BASE_URL` | `'http://127.0.0.1:8081/<Unit>'` | 桥接程序的 HTTP 前缀 |
| 超时 | `HTTP_CALL_TIMEOUT` | `Duration(seconds: 30)` | 超时 |
| Debug 日志 | `DEBUG_LOG` | `false` | 是否打印请求 / 响应 |

#### 5.13.8 错误处理

- **异常类型**：`api.HttpCallError`（实现 `Exception`）。
- **字段**：`.message`（String）、`.code`（int）、`.httpStatus`（int）。

#### 5.13.9 关闭

无（Dart 的 `http.Client` 在每次请求后释放，或进程退出即释放）。

---

### 5.14 Swift（模式 A）

#### 5.14.1 产物

```
<Unit>_http_json_call_swift.swift
```

#### 5.14.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| Swift 5.9+ | — | ✅ |
| `Foundation` | 标准库 | ✅ |
| `FoundationNetworking`（Linux） | — | Linux 需要 |
| `Dispatch` | 标准库 | ✅ |

**不需要** LingoFuse 原生库。

#### 5.14.3 平台

- **编译器 / 运行时**：Swift 5.9+。
- **操作系统**：macOS 12+、iOS 15+（异步 API 需要）、Linux、Windows。**macOS 11 / iOS 14 只能使用同步 API**。

#### 5.14.4 引入

**方式 A：同一模块内**

```swift
// 直接把生成的 .swift 文件加入 target
let sum = try <Unit>HttpJsonClient.Add(1, 2)
```

**方式 B：作为 SPM 包**

把 `.swift` 文件放入 `Sources/<ModuleName>/` 目录。

#### 5.14.5 初始化

```swift
<Unit>HttpJsonClient.baseUrl = "http://127.0.0.1:8081/<Unit>"
<Unit>HttpJsonClient.timeout = 30.0
<Unit>HttpJsonClient.debugLog = false
```

**不需要** LingoFuse 初始化。

#### 5.14.6 同步调用

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

#### 5.14.7 异步调用

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

#### 5.14.8 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `baseUrl` | `String` | `"http://127.0.0.1:8081/<Unit>"` | 桥接程序的 HTTP 前缀 |
| `timeout` | `TimeInterval` | `30.0` | 超时（秒） |
| `debugLog` | `Bool` | `false` | 是否打印请求 / 响应 |

#### 5.14.9 错误处理

- **错误类型**：`<Unit>HttpJsonClient.HTTPCallError`（实现 `Error` + `CustomStringConvertible`）。
- **字段**：`.message`（String）、`.code`（Int）、`.httpStatus`（Int）。

#### 5.14.10 关闭

无（`URLSession.shared` 是进程级单例）。

---

### 5.15 Ruby（模式 A）

#### 5.15.1 产物

```
<Unit>_http_json_call.rb
```

#### 5.15.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| Ruby 2.7+ / 3.0+ | — | ✅ |
| `net/http`、`json`、`uri` | 标准库 | ✅ |

**不需要** LingoFuse 原生库。

#### 5.15.3 平台

- **运行时**：Ruby 2.7+ / 3.0+。
- **操作系统**：Windows、Linux、macOS、FreeBSD 等所有 Ruby 支持的平台。

#### 5.15.4 引入

```ruby
require_relative '<Unit>_http_json_call'
```

#### 5.15.5 初始化

```ruby
<ModuleName>.base_url = "http://127.0.0.1:8081/<Unit>"
<ModuleName>.http_call_timeout = 30.0
<ModuleName>.debug_log = false
```

**`<ModuleName>`** 是生成的 Ruby 模块名（例如 `<Unit>HttpJsonCall`）。

**陷阱**：**不要**给 `HTTP_CALL_BASE_URL` 赋值。它是只读兼容读取器。赋值会被 Ruby 解析为常量赋值，抛 `dynamic constant assignment`。

#### 5.15.6 调用（只有同步）

```ruby
begin
  sum = <ModuleName>.Add(1, 2)
  puts "Add(1, 2) = #{sum}"
rescue <ModuleName>::HTTPCallError => e
  warn "Add failed: #{e.message}, code=#{e.code}, http=#{e.http_status}"
end
```

**并发调用**用 `Thread.new { ... }`：

```ruby
threads = []
threads << Thread.new { <ModuleName>.Add(1, 2) }
threads << Thread.new { <ModuleName>.Sub(5, 3) }
threads.each(&:join)
```

#### 5.15.7 配置

| 配置项 | 读写 | 默认值 |
|--------|------|--------|
| `base_url` | 读写 | `'http://127.0.0.1:8081/<Unit>'` |
| `http_call_timeout` | 读写 | `30.0` |
| `debug_log` | 读写 | `false`（或 `LINGOFUSE_DEBUG=1`） |
| `HTTP_CALL_BASE_URL` | **只读** | 同 `base_url` |
| `HTTP_CALL_TIMEOUT` | **只读** | 同 `http_call_timeout` |
| `DEBUG_LOG` | **只读** | 同 `debug_log` |

#### 5.15.8 错误处理

- **异常类型**：`<ModuleName>::HTTPCallError`（继承自 `StandardError`）。
- **字段**：`.code`（Integer）、`.http_status`（Integer）、`.message`（String）。

#### 5.15.9 关闭

无（Ruby 的 `Net::HTTP` 每次新建）。

---

### 5.16 Zig（模式 B）

#### 5.16.1 产物

```
<Unit>_http_json_call_zig.zig
```

#### 5.16.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| Zig 0.13+ | — | ✅ |
| `lingofuse` Zig 绑定（`src/lingofuse.zig`） | LingoFuse 发行版 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |

#### 5.16.3 平台

- **编译器**：Zig 0.13+。
- **操作系统**：Windows、Linux、macOS。**受 LingoFuse 原生库支持范围限制**。

#### 5.16.4 引入

```zig
const call = @import("<Unit>_http_json_call_zig.zig");
```

**`build.zig`** 需要：

```zig
const lf_dep = b.dependency("lingofuse", .{ .target = target, .optimize = optimize });
exe_mod.addImport("lingofuse", lf_dep.module("lingofuse"));
```

#### 5.16.5 初始化

```zig
// 1. 加载 LingoFuse
try lf.framework.init();
defer lf.framework.deinit();

// 2. 配置选项
lf.options.setWaitConnectionReadyOk(false) catch {};
lf.options.setOverlapConnection(true) catch {};
lf.options.setQuiet(true) catch {};

// 3. 连接端点
lf.framework.resetPrepare();
_ = lf.framework.prepareClient("ipc:<Unit>_http_json", null) catch |e| {
    std.debug.print("[FATAL] prepareClient failed: {}\n", .{e});
    return;
};
_ = lf.framework.prepareDone();

// 4. 配置 Base URL（默认已是 http://127.0.0.1:8081/<Unit>）
call.HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>";
```

#### 5.16.6 同步调用

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

#### 5.16.7 异步调用

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
// 轮询 w.done
```

#### 5.16.8 配置

| 配置项 | 类型 | 默认值 |
|--------|------|--------|
| `HTTP_CALL_BASE_URL` | `[]const u8` | `"http://127.0.0.1:8081/<Unit>"` |
| `BRIDGE_APP_NAME` | `[:0]const u8` | `"__lf_http_bridge__"` |
| `BRIDGE_API_NAME` | `[:0]const u8` | `"__lf_outbound_post__"` |
| `BRIDGE_TIMEOUT_MS` | `u64` | `35_000` |
| `DEFAULT_HTTP_TIMEOUT_SEC` | `u32` | `30` |
| `DEBUG_LOG` | `bool` | `false` |

#### 5.16.9 错误处理

- **错误类型**：`call.HttpCallError`（`error{}` 枚举）。
- **详细信息**：`call.lastError()` 返回 `*const ErrorInfo`（含 `kind`、`code`、`http_status`、`message()`）。

#### 5.16.10 关闭

```zig
lf.framework.exitMainThread();
lf.framework.shutdown();
lf.framework.deinit();
```

---

### 5.17 Erlang（模式 A）

#### 5.17.1 产物

```
<Unit>_http_json_call.erl
```

#### 5.17.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| Erlang/OTP 25+ | — | ✅ |
| `inets`（`httpc`） | OTP 标准库 | ✅ |
| `ssl` | OTP 标准库 | ✅ |
| `json` Erlang 库 | Hex / 手动 | ✅ |

**不需要** LingoFuse 原生库。

#### 5.17.3 平台

- **运行时**：Erlang/OTP 25+。
- **操作系统**：Windows、Linux、macOS、FreeBSD 等所有 Erlang/OTP 支持的平台。

#### 5.17.4 引入

```erlang
-module(my_app).
-export([run/0]).

run() ->
    %% 加载生成的模块
    <Unit>_http_json_call:set_base_url(<<"http://127.0.0.1:8081/<Unit>">>),
    <Unit>_http_json_call:set_timeout(30000),
    ...
```

**`<Unit>_http_json_call.erl`** 必须编译为 `.beam` 并在 code path 上。

#### 5.17.5 初始化

```erlang
ok = <Unit>_http_json_call:set_base_url(<<"http://127.0.0.1:8081/<Unit>">>),
ok = <Unit>_http_json_call:set_timeout(30000).
```

**不需要** LingoFuse 初始化。

#### 5.17.6 同步调用

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

#### 5.17.7 异步调用

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

#### 5.17.8 配置

| 配置项 | 函数 | 默认值 |
|--------|------|--------|
| Base URL | `set_base_url/1` / `get_base_url/0` | `<<"http://127.0.0.1:8081/<Unit>">>` |
| 超时（毫秒） | `set_timeout/1` / `get_timeout/0` | `30000` |

#### 5.17.8.1 错误格式

- **成功**：`{ok, Result}`
- **服务错误**：`{error, {service_error, Code, Msg}}`
- **HTTP 错误**：`{error, {http_status, Status, Body}}`
- **传输错误**：`{error, {http_error, Reason}}`
- **JSON 解析失败**：`{error, {json_decode_failed, Reason}}`

#### 5.17.9 关闭

无（Erlang 的 `httpc` 是 OTP 级应用，进程退出即释放）。

---

### 5.18 Fortran（模式 B）

#### 5.18.1 产物

```
<Unit>_http_json_call_mod.f90
```

#### 5.18.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| gfortran 9+ / ifort / flang | — | ✅ |
| `lf_fortran_mod.f90` | LingoFuse 发行版 | ✅ |
| `lf_fortran.cpp` | LingoFuse 发行版 | ✅ |
| `LingoFuse.c` | LingoFuse 发行版 | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |

#### 5.18.3 平台

- **编译器**：gfortran 9+ / ifort / flang。
- **操作系统**：Windows、Linux、macOS。**受 `lf_fortran.cpp` + LingoFuse C ABI 原生库支持范围限制**。

#### 5.18.4 引入

```fortran
program my_app
  use iso_c_binding
  use lf_fortran_mod
  use <Unit>_http_json_call_mod
  implicit none
  ! ...
end program
```

#### 5.18.5 初始化

```fortran
call http_call_init( &
    base_url = 'http://127.0.0.1:8081/<Unit>', &
    bridge_app = '__lf_http_bridge__', &
    bridge_api = '__lf_outbound_post__', &
    call_timeout_ms = 60000_c_int64_t, &
    http_timeout_sec = 25.0d0)
```

**注意**：Fortran 的 `http_call_init` **不**加载 LingoFuse 原生库——那是 `lf_fortran_mod` 的职责。**调用方必须先完成 LingoFuse 初始化**：

```fortran
! 伪代码——具体 API 见 lf_fortran_mod
call lf_load_library()
call lf_prepare_client('ipc:<Unit>_http_json', c_null_ptr)
call lf_prepare_done()
```

#### 5.18.6 同步调用

```fortran
integer(c_int64_t) :: sum
sum = add_call(1_c_int64_t, 2_c_int64_t)
print *, 'Add(1, 2) = ', sum
```

**过程（procedure）**：

```fortran
call log_call('hello')
```

**失败处理**：Fortran 版没有异常机制。失败时返回类型零值（`0` / `0.0d0` / `''`），或 `c_null_ptr`。**调用方需要检查返回值是否为零值**，或改用异步 API 的 `ok` 输出参数。

#### 5.18.7 异步调用

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

#### 5.18.8 配置

| 配置项 | 类型 | 默认值 |
|--------|------|--------|
| `HTTP_CALL_BASE_URL` | `character(len=512)` | `'http://127.0.0.1:8081/<Unit>'` |
| `HTTP_BRIDGE_APP_NAME` | `character(len=128)` | `'__lf_http_bridge__'` |
| `HTTP_BRIDGE_API_NAME` | `character(len=128)` | `'__lf_outbound_post__'` |
| `HTTP_CALL_TIMEOUT_MS` | `integer(c_int64_t)` | `0`（默认 60000） |
| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `real(c_double)` | `0.0d0`（默认 25.0） |

#### 5.18.9 错误处理

- **同步调用**：返回类型零值（`0` / `0.0d0` / `''`），无异常机制。
- **异步调用**：`*_read_async_result(handle, ok)` 的 `ok` 输出参数为 `logical`。
- **返回值检查**：调用方必须显式判断。

#### 5.18.10 关闭

```fortran
call lf_exit_main_thread()
call lf_shutdown()
```

---

### 5.19 Julia（模式 B）

#### 5.19.1 产物

```
<Unit>_http_json_call.jl
```

#### 5.19.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| Julia 1.9+ | — | ✅ |
| `LingoFuse` Julia 绑定 | LingoFuse 发行版 | ✅ |
| `JSON3` | Julia registry | ✅ |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |
| **`--threads=2` 或更多** | — | ✅ |

#### 5.19.3 平台

- **运行时**：Julia 1.9+（推荐 1.10+）。
- **操作系统**：Windows、Linux、macOS、FreeBSD。**受 LingoFuse Julia 绑定支持范围限制**。

#### 5.19.4 引入

```julia
include("<Unit>_http_json_call.jl")
import .<Unit>HttpJsonCall
```

或作为项目包：

```julia
using <Unit>HttpJsonCall
```

#### 5.19.5 初始化

**必须在 `--threads=2` 或更多的 Julia 进程里**：

```julia
using LingoFuse
import LingoFuse: reset_prepare, prepare_client, prepare_done,
                  set_option, start_callback_consumer,
                  stop_callback_consumer

# 1. 启动回调消费者（必需）
start_callback_consumer()

# 2. 配置
set_option("Wait_Connection_ReadyOk", "True")
set_option("Overlap_Connection", "True")
reset_prepare()

# 3. 连接端点
prepare_client("ipc:<Unit>_http_json", nothing)
prepare_done()

# 4. 配置 Base URL
<Unit>HttpJsonCall.HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<Unit>"
```

#### 5.19.6 同步调用

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

#### 5.19.7 异步调用

```julia
task = <Unit>HttpJsonCall.add_async(1, 2)
try
    sum = fetch(task)
    println("Add(1, 2) = $sum")
catch e
    println("Add failed: $e")
end
```

#### 5.19.8 配置

| 配置项 | 类型 | 默认值 |
|--------|------|--------|
| `HTTP_CALL_BASE_URL` | `String` | `"http://127.0.0.1:8081/<Unit>"` |
| `HTTP_BRIDGE_APP_NAME` | `String` | `""`（即 `"__lf_http_bridge__"`） |
| `HTTP_BRIDGE_API_NAME` | `String` | `""`（即 `"__lf_outbound_post__"`） |
| `HTTP_CALL_TIMEOUT_MS` | `Int64` | `Int64(0)`（默认 60000） |
| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `Float64` | `0.0`（默认 25.0） |

#### 5.19.9 错误处理

- **异常类型**：`<Unit>HttpJsonCall.HTTPCallError`（实现 `Exception`）。
- **字段**：`.msg`（String）、`.code`（Int）、`.http_status`（Int）。

#### 5.19.10 关闭

```julia
stop_callback_consumer()
```

---

### 5.20 R（模式 B）

#### 5.20.1 产物

```
<Unit>_http_json_call.R
```

#### 5.20.2 依赖

| 依赖 | 来源 | 必需 |
|------|------|:----:|
| R 4.0+ | — | ✅ |
| `lingofuse` R 包 | LingoFuse 发行版 | ✅ |
| `jsonlite` | CRAN | ✅ |
| `future`（仅异步） | CRAN | 异步需要 |
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 发行版 | ✅（运行时） |
| `z_ipc_64.dll` | LingoFuse 发行版 | ✅（运行时） |

#### 5.20.3 平台

- **运行时**：R 4.0+。
- **操作系统**：Windows、Linux、macOS。**受 `lingofuse` R 包支持范围限制**。

#### 5.20.4 引入

```r
source("<Unit>_http_json_call.R")
```

或作为 package 引入。

#### 5.20.5 初始化

```r
# 1. 设置 LingoFuse 运行时目录（可选，若默认探测失败）
LF_CLIENT_RUNTIME_DIR <- "C:/LingoFuse/Binary"

# 2. 配置 Base URL（默认已是 http://127.0.0.1:8081/<Unit>）
HTTP_CALL_BASE_URL <- "http://127.0.0.1:8081/<Unit>"

# 3. 初始化 LingoFuse 客户端
lf_http_client_init()

# 4. 可选：异步需要 future 包
if (requireNamespace("future", quietly = TRUE)) {
    future::plan(future::sequential)
}
```

`lf_http_client_init()` 内部会：

- `lingofuse::lf_load(runtime_dir)`
- `lingofuse::lf_prepare_client(endpoint, NULL)`
- `lingofuse::lf_prepare_done()`

#### 5.20.6 同步调用

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

#### 5.20.7 异步调用

```r
# 必须 future::plan(future::sequential)
future::plan(future::sequential)

fut <- add_async(1, 2,
    on_success = function(r) cat("Add = ", r, "\n", sep = ""),
    on_error = function(msg, code) cat("Add failed: ", msg, " (code=", code, ")\n", sep = ""))
value(fut)  # 阻塞等待
```

**警告**：`*_async` 变体**必须** `future::plan("sequential")`。`multisession` / `multicore` 会 fork worker 进程，而 LingoFuse 运行时在子进程中没有初始化，导致内部调用永远失败。生成的 `*_async` 函数会在 dispatch 时检查，若计划不兼容则立刻报错。

**要并发就用同步函数 + 你自己的线程池。**

#### 5.20.8 配置

| 配置项 | 类型 | 默认值 |
|--------|------|--------|
| `HTTP_CALL_BASE_URL` | `character` | `"http://127.0.0.1:8081/<Unit>"` |
| `HTTP_BRIDGE_APP_NAME` | `character` | `"__lf_http_bridge__"` |
| `HTTP_BRIDGE_API_NAME` | `character` | `"__lf_outbound_post__"` |
| `HTTP_CALL_TIMEOUT_MS` | `integer` | `60000` |
| `HTTP_CALL_DEFAULT_TIMEOUT_S` | `numeric` | `25.0` |
| `LF_CLIENT_ENDPOINT` | `character` | `"ipc:<Unit>_http_json"` |
| `LF_CLIENT_RUNTIME_DIR` | `character` 或 `NULL` | `NULL`（自动探测） |

#### 5.20.9 错误处理

- **异常类型**：`http_call_error`（`structure(class = c("http_call_error", "error", "condition"), list(...))`）。
- **字段**：`e$message`（character）、`e$code`（integer）、`e$http_status`（integer）。

#### 5.20.10 关闭

```r
lf_http_client_shutdown()
```

内部调用 `lingofuse::lf_exit_main_thread()` + `lingofuse::lf_shutdown()`。

---

## 6. 平台与操作系统支持矩阵

### 6.1 按语言

| 语言 | 编译器 / 运行时 | Windows | Linux | macOS | 其他 OS | 备注 |
|------|----------------|:-------:|:-----:|:-----:|---------|------|
| Pascal | FPC 3.2+ / Delphi 11+ | ✅ | ✅ | ✅ | 受 LingoFuse 原生库限制 | 模式 B |
| Python | Python 3.8+ | ✅ | ✅ | ✅ | FreeBSD、OpenBSD 等 | 模式 A |
| C++ | C++17 编译器 | ✅ | ✅ | ✅ | 受 LingoFuse 原生库限制 | 模式 B |
| C# | .NET 8.0+ | ✅ | ✅ | ✅ | 受 LingoFuse .NET 绑定限制 | 模式 B |
| JavaScript | 现代浏览器 | ✅ | ✅ | ✅ | iOS、Android、ChromeOS | 模式 A |
| Node.js | Node.js 18+ | ✅ | ✅ | ✅ | FreeBSD、OpenBSD | 模式 A |
| TypeScript | Node.js 18+ / 浏览器 | ✅ | ✅ | ✅ | 同运行环境 | 模式 A |
| PHP | PHP 7.4+ | ✅ | ✅ | ✅ | FreeBSD 等 | 模式 A |
| Rust | Rust 1.70+ | ✅ | ✅ | ✅ | FreeBSD、WASM、嵌入式 | 模式 A |
| Go | Go 1.21+ | ✅ | ✅ | ✅ | FreeBSD、OpenBSD、NetBSD、Plan 9、Android、iOS、WASM | 模式 A |
| Java | JDK 11+ | ✅ | ✅ | ✅ | Solaris、AIX | 模式 A |
| Delphi | Delphi 10.3+ | ✅ | ✅ | ✅ | iOS、Android（受 Delphi 版本限制） | 模式 A |
| Dart | Dart 3.0+ | ✅ | ✅ | ✅ | iOS、Android、Web | 模式 A |
| Swift | Swift 5.9+ | ✅ | ✅ | ✅ | iOS（异步需 macOS 12+ / iOS 15+） | 模式 A |
| Ruby | Ruby 2.7+ / 3.0+ | ✅ | ✅ | ✅ | FreeBSD 等 | 模式 A |
| Zig | Zig 0.13+ | ✅ | ✅ | ✅ | 受 LingoFuse 原生库限制 | 模式 B |
| Erlang | Erlang/OTP 25+ | ✅ | ✅ | ✅ | FreeBSD 等 | 模式 A |
| Fortran | gfortran 9+ | ✅ | ✅ | ✅ | 受 `lf_fortran.cpp` + LingoFuse 原生库限制 | 模式 B |
| Julia | Julia 1.9+ | ✅ | ✅ | ✅ | FreeBSD | 模式 B，`--threads=2` 必须 |
| R | R 4.0+ | ✅ | ✅ | ✅ | 受 `lingofuse` R 包限制 | 模式 B |

### 6.2 按 OS

| 操作系统 | 模式 A 支持 | 模式 B 支持 |
|----------|:-----------:|:-----------:|
| Windows（x86 / x64 / arm64） | ✅ Python、JS、Node.js、TS、PHP、Rust、Go、Java、Delphi、Dart、Swift、Ruby、Erlang | ✅ Pascal、C++、C#、Zig、Fortran、Julia、R |
| Linux（x64 / arm64） | ✅ Python、JS、Node.js、TS、PHP、Rust、Go、Java、Dart、Swift、Ruby、Erlang | ✅ Pascal、C++、C#、Zig、Fortran、Julia、R |
| macOS（x64 / arm64） | ✅ Python、JS、Node.js、TS、PHP、Rust、Go、Java、Delphi、Dart、Swift、Ruby、Erlang | ✅ Pascal、C++、C#、Zig、Fortran、Julia、R |
| iOS / iPadOS | ✅ JavaScript、Swift、Dart、Delphi | ❌（LingoFuse 原生库不支持） |
| Android | ✅ JavaScript、Dart、Delphi | ❌ |
| FreeBSD / OpenBSD / NetBSD | ✅ Python、Rust、Go、Ruby、Erlang | ❌ |
| 浏览器（任何 OS） | ✅ JavaScript | ❌ |
| WASM | ✅ Rust、Go | ❌ |

**关键结论**：

- **移动端（iOS / Android）只能用模式 A**。因为 LingoFuse 原生库不支持这些平台。
- **嵌入式 / WASM 只能用模式 A**。同上。
- **桌面 / 服务器（Windows / Linux / macOS）模式 A 与模式 B 都可用**。

### 6.3 按"是否需要 LingoFuse 原生库"

| 语言 | 需要 `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | 需要 `z_ipc_*` | 需要 `bridge.py` |
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

**模式 A 的最大优势**：**不需要任何 LingoFuse 原生库**，只需要 `bridge.py` 在运行。这让 Python / JS / Node.js / TS / PHP / Rust / Go / Java / Delphi / Dart / Swift / Ruby / Erlang 的集成变得极其简单——不需要考虑 DLL 加载、跨平台二进制分发、原生库版本兼容。

---

## 7. 横向对比速查表

### 7.1 接入方式

| 语言 | 模式 | 需要初始化 LingoFuse | 引入方式 | 同步 API | 异步 API |
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
| Go | A | ❌ | `import "..."` / 同包 | ✅ | ✅ |
| Java | A | ❌ | `import ...HttpJsonClient` | ✅ | ❌ |
| Delphi | A | ❌ | `uses <Unit>_http_json_call_delphi;` | ✅ | ✅ |
| Dart | A | ❌ | `import '..._dart.dart' as api` | ❌ | ✅ |
| Swift | A | ❌ | 同 target / SPM 包 | ✅ | ✅（macOS 12+ / iOS 15+） |
| Ruby | A | ❌ | `require_relative '..._ruby'` | ✅ | ❌ |
| Zig | B | ✅ | `const call = @import("..._zig.zig")` | ✅ | ✅ |
| Erlang | A | ❌ | 加载 `<Unit>_http_json_call.beam` | ✅ | ✅ |
| Fortran | B | ✅ | `use <Unit>_http_json_call_mod` | ✅ | ✅ |
| Julia | B | ✅ | `include("..._jl")` / `using ...` | ✅ | ✅ |
| R | B | ✅ | `source("..._R")` | ✅ | ✅ |

### 7.2 错误类型

| 语言 | 错误类型 | 主要字段 |
|------|----------|----------|
| Pascal | `EHTTPCallError` | `.Message`、`.Code`、`.HttpStatus` |
| Python | `HTTPCallError` | `.message`、`.code`、`.http_status` |
| C++ | `HTTPCallError` | `.what()`、`.code`、`.http_status` |
| C# | `HTTPCallError` | `.Message`、`.Code`、`.HttpStatus` |
| JavaScript | `LFHttpCallError` | `.message`、`.code`、`.httpStatus` |
| Node.js | `HTTPCallError` | `.message`、`.code`、`.httpStatus` |
| TypeScript | `HttpJsonCallError` | `.message`、`.code`、`.httpStatus` |
| PHP | `HttpJsonCallError` | `.getMessage()`、`.getCode()`、`.httpStatus` |
| Rust | `HttpCallError` | `.message`、`.code`、`.http_status` |
| Go | `HTTPCallError` | `.Message`、`.Code`、`.HTTPStatus` |
| Java | `HTTPCallException` | `.getMessage()`、`.code`、`.httpStatus` |
| Delphi | `EHTTPCallError` | `.Message`、`.Code`、`.HttpStatus` |
| Dart | `HttpCallError` | `.message`、`.code`、`.httpStatus` |
| Swift | `HTTPCallError` | `.message`、`.code`、`.httpStatus` |
| Ruby | `HTTPCallError` | `.message`、`.code`、`.http_status` |
| Zig | `HttpCallError` + `lastError()` | `lastError().code`、`lastError().http_status` |
| Erlang | `{error, Reason}` | `{service_error, Code, Msg}` / `{http_status, Status, Body}` |
| Fortran | 零值返回 / `ok` 输出参数 | 无异常机制 |
| Julia | `HTTPCallError` | `.msg`、`.code`、`.http_status` |
| R | `http_call_error` | `e$message`、`e$code`、`e$http_status` |

### 7.3 配置入口

| 语言 | Base URL | 超时 | Debug |
|------|----------|------|-------|
| Pascal | `HTTP_CALL_BASE_URL` | `HTTP_CALL_TIMEOUT_MS` | （无内置） |
| Python | `HTTP_CALL_BASE_URL` | `HTTP_CALL_TIMEOUT` | `DEBUG_LOG` |
| C++ | `HTTP_CALL_BASE_URL` | `HTTP_CALL_DEFAULT_TIMEOUT_S` | （无内置） |
| C# | `HttpJsonCallConfig.BaseUrl` | `HttpJsonCallConfig.HttpTimeoutSec` | `HttpJsonCallConfig.DebugLog` |
| JavaScript | `<Unit>Api.setBaseUrl(url)` | （无） | （无） |
| Node.js | `HTTP_CALL_BASE_URL` | `HTTP_CALL_TIMEOUT_MS` | `DEBUG_LOG` |
| TypeScript | `HttpJsonCallConfig.baseUrl` | `HttpJsonCallConfig.httpTimeoutMs` | `HttpJsonCallConfig.debugLog` |
| PHP | `HttpJsonCallConfig::$baseUrl` | `HttpJsonCallConfig::$httpTimeoutSec` | `HttpJsonCallConfig::$debugLog` |
| Rust | `set_base_url(&str)` | `set_timeout_secs(u64)` | `set_debug_log(bool)` |
| Go | `HTTPCallBaseURL` | `HTTPCallTimeout` | `DebugLog` |
| Java | `HTTP_CALL_BASE_URL` | `HTTP_CALL_TIMEOUT` | （无内置） |
| Delphi | `HTTP_CALL_BASE_URL` | `HTTP_CALL_TIMEOUT_MS` | （无内置） |
| Dart | `setBaseUrl(url)` / `DEFAULT_BASE_URL` | `HTTP_CALL_TIMEOUT` | `DEBUG_LOG` |
| Swift | `baseUrl` | `timeout` | `debugLog` |
| Ruby | `base_url`（**不要**用 `HTTP_CALL_BASE_URL`） | `http_call_timeout` | `debug_log` |
| Zig | `HTTP_CALL_BASE_URL` | `DEFAULT_HTTP_TIMEOUT_SEC` + `BRIDGE_TIMEOUT_MS` | `DEBUG_LOG` |
| Erlang | `set_base_url/1` | `set_timeout/1` | （无内置） |
| Fortran | `HTTP_CALL_BASE_URL` | `HTTP_CALL_DEFAULT_TIMEOUT_S` + `HTTP_CALL_TIMEOUT_MS` | （无内置） |
| Julia | `HTTP_CALL_BASE_URL` | `HTTP_CALL_DEFAULT_TIMEOUT_S` + `HTTP_CALL_TIMEOUT_MS` | `DEBUG_LOG` |
| R | `HTTP_CALL_BASE_URL` | `HTTP_CALL_DEFAULT_TIMEOUT_S` + `HTTP_CALL_TIMEOUT_MS` | `DEBUG_LOG` |

### 7.4 线程模型

| 语言 | 同步调用的线程 | 异步回调的线程 | 注意事项 |
|------|----------------|----------------|----------|
| Pascal | 调用方线程（阻塞） | 工作线程 | 更新 UI 需 `TThread.Queue` |
| Python | 调用方线程（阻塞） | `asyncio` 事件循环线程 | 标准 `asyncio.run(main())` |
| C++ | 调用方线程（阻塞） | 工作线程 | 回调内不要访问未加锁共享状态 |
| C# | 调用方线程（阻塞） | 工作线程 | 用 `TaskCompletionSource` |
| JavaScript | 无（只有异步） | 微任务队列 | 标准 Promise |
| Node.js | 无（只有异步） | 微任务队列 | 标准 Promise |
| TypeScript | 无（只有异步） | 微任务队列 | 标准 Promise |
| PHP | 调用方线程（阻塞） | 无（只有同步） | — |
| Rust | 调用方线程（阻塞） | `tokio` worker | 用 `#[tokio::main]` |
| Go | 调用方 goroutine（阻塞） | 新 goroutine（channel） | 标准 channel 模式 |
| Java | 调用方线程（阻塞） | 无（只有同步） | — |
| Delphi | 调用方线程（阻塞） | 工作线程 | 更新 UI 需 `TThread.Queue` |
| Dart | 无（只有异步） | 微任务队列 | 标准 Future |
| Swift | 调用方线程（阻塞） | `URLSession` 回调队列（同步）/ 并发任务（异步） | `@unchecked Sendable` 是正确标注 |
| Ruby | 调用方线程（阻塞） | 无（只有同步） | 并发用 `Thread.new` |
| Zig | 调用方线程（阻塞） | LingoFuse async worker | 用 `std.atomic.Value(bool)` 轮询 |
| Erlang | 调用方进程（阻塞） | 新进程（spawn） | 标准 `receive` |
| Fortran | 调用方线程（阻塞） | LingoFuse async worker | 用 `c_funloc` 回调 |
| Julia | 调用方 Task（阻塞） | `Threads.@spawn` | 必须 `--threads=2` |
| R | 调用方线程（阻塞） | `future` worker | **必须** `future::plan("sequential")` |

---

## 8. 常见集成问题

### 8.1 所有语言

| 症状 | 原因 | 修复 |
|------|------|------|
| `Network error` / `Connection refused` | **桥接程序未运行** | 启动 `bridge.py` |
| `code=-3` | 桥接程序预检查缓存未更新 | 桥接加 `--no-precheck` |
| `code=-4` | 桥接协议错误 | 检查桥接与服务版本 |
| 调用超时 | 服务侧阻塞 / 桥接阻塞 | 看服务侧日志 |
| `int64` 精度损失 | JS `Number` / PHP int | 服务侧返回字符串 |

### 8.2 模式 A 专属

| 症状 | 原因 | 修复 |
|------|------|------|
| `Connection refused`（不需要 LingoFuse） | 桥接程序未运行 | 启动 `bridge.py` |
| CORS 错误（浏览器） | 桥接未返回 `Access-Control-Allow-Origin` | 桥接加 `--cors '*'` |
| `file://` 下无法 fetch | 浏览器 `file://` 限制 | 用 `python3 -m http.server` 提供 |

### 8.3 模式 B 专属

| 症状 | 原因 | 修复 |
|------|------|------|
| `LF_LoadLibrary` 返回非 1 | LingoFuse 原生库缺失或架构不匹配 | 复制正确的 `LingoFuse64.dll` / `liblingofuse.so` |
| `LF_PrepareClient returned -1` | 端点已被占用 / 无效 | 检查端点字符串；杀旧进程 |
| `LF_PrepareDone returned 0` | 同一进程已调用过 | 重启进程 |
| `no found app("__lf_http_bridge__")` | 桥接程序未运行 | 启动 `bridge.py` |
| `no found app("<Unit>")` | 服务侧未运行 | 启动服务 |
| `LF_Async_CallEx failed` | LingoFuse 主循环未运行 | 检查 `LF_PrepareDone` 是否返回 1 |

### 8.4 语言专属

| 语言 | 症状 | 原因 | 修复 |
|------|------|------|------|
| Ruby | `dynamic constant assignment` | 给 `HTTP_CALL_BASE_URL` 赋值 | 用 `Module.base_url = "..."` |
| R | `*_async variants require future::plan('sequential')` | future 计划不兼容 | `future::plan(future::sequential)` |
| Julia | `--threads=2 or more required` | 单线程 | 加 `--threads=2` |
| Julia | `prepare_client returned -1` | 端点已被占用 | 换端点或杀旧进程 |
| C# | `DllNotFoundException: LingoFuse64` | DLL 未复制 | 复制到 bin 目录 |
| C# | `Could not load type 'lingofuse.AppHandle'` | LingoFuse.dll 引用缺失 | `dotnet add reference` |
| Swift | `HTTPCallError`（异步 pass 未运行） | macOS 12 以下 | 只用同步 pass |
| PHP | `Call to undefined function curl_init()` | 未装 curl 扩展 | `apt install php-curl` 或 `allow_url_fopen=On` |
| Zig | `build.zig` fingerprint mismatch | 指纹过期 | 按报错信息替换 `.fingerprint` |
| Erlang | `no such file or directory: lingofuse_nif.dll` | NIF 缺失 | 复制到 `priv/` |
| Fortran | `undefined reference to 'lf_*'` | `lf_fortran.cpp` 未链接 | 用 `setup_fortran_tests.ps1` |
| Go | `module not found` | 未 `go get` | `go get github.com/PassByYou888/LingoFuse/go` |

### 8.5 桥接程序名与端点字符串的常见错误

| 错误写法 | 正确写法 |
|----------|----------|
| `Calculator`（端点） | `ipc:Calculator_http_json` |
| `ipc:calculator_http_json`（大小写） | `ipc:Calculator_http_json`（与 `<UnitName>` 完全一致） |
| `HTTP_CALL_BASE_URL = "http://127.0.0.1:8081"`（缺 App 名） | `"http://127.0.0.1:8081/Calculator"` |
| `HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/Calculator/"`（尾部斜杠） | 生成代码会自动去掉，但建议不写 |
| `BridgeAppName = ""`（模式 B，C++ / C# / Julia 等） | 留空即用默认 `__lf_http_bridge__`；但显式设置更清晰 |
| `BridgeApiName = "__lf_http_bridge__"`（写错） | `"__lf_outbound_post__"` |

---

## 附录：一页速查表

| 语言 | 模式 | 需要原生库 | 需要 init | 同步 | 异步 | 引入方式 |
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
| Swift | A | ❌ | ❌ | ✅ | ✅ | 同 target / SPM |
| Ruby | A | ❌ | ❌ | ✅ | ❌ | `require_relative` |
| Zig | B | ✅ | ✅ | ✅ | ✅ | `@import` |
| Erlang | A | ❌ | ❌ | ✅ | ✅ | 加载 `.beam` |
| Fortran | B | ✅ | ✅ | ✅ | ✅ | `use` |
| Julia | B | ✅ | ✅ | ✅ | ✅ | `include` / `using` |
| R | B | ✅ | ✅ | ✅ | ✅ | `source` |

**桥接程序（`bridge.py` / `bridge.exe`）必须始终运行。** 所有 20+ 种 Call 库都通过它访问服务——区别只在于"直接 HTTP"（模式 A）还是"通过 LingoFuse C ABI"（模式 B）。

**模式 A 不需要 LingoFuse 原生库；模式 B 需要。** 这是选择模式的决定性因素。
