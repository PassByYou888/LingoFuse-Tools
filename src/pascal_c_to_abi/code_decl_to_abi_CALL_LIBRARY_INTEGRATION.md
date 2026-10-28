# code_decl_to_abi — 各语言 Call 库接入指南

> **文档定位**: 详细说明 `code_decl_to_abi` 生成的 **Call 库**（调用侧）在 17 种目标语言中的接入方式，涵盖每个库支持的调用变体、异步能力、开发平台要求、操作系统支持、依赖包、安装方式、最小接入代码与关键注意事项。
>
> **前置阅读**: `code_decl_to_abi_USER_GUIDE.md`（整体工具与工作流）、`code_decl_to_abi_TESTING_GUIDE.md`（测试方法与验证）。
>
> **文档语言**: 中文。
>
> **生成代码语言**: 英文。

---

## 目录

1. [术语与变体命名规则](#1-术语与变体命名规则)
2. [总览能力矩阵](#2-总览能力矩阵)
3. [各语言详细接入](#3-各语言详细接入)
   - [3.1 Pascal](#31-pascal)
   - [3.2 Python](#32-python)
   - [3.3 C++](#33-c)
   - [3.4 C#](#34-c)
   - [3.5 Rust](#35-rust)
   - [3.6 Go](#36-go)
   - [3.7 Java](#37-java)
   - [3.8 Node.js](#38-nodejs)
   - [3.9 TypeScript](#39-typescript)
   - [3.10 Erlang](#310-erlang)
   - [3.11 Julia](#311-julia)
   - [3.12 Zig](#312-zig)
   - [3.13 Swift](#313-swift)
   - [3.14 Ruby](#314-ruby)
   - [3.15 Fortran](#315-fortran)
   - [3.16 Dart](#316-dart)
   - [3.17 R](#317-r)
4. [跨语言互操作注意事项](#4-跨语言互操作注意事项)
5. [常见问题](#5-常见问题)

---

## 1. 术语与变体命名规则

### 1.1 Call 库的角色

Call 库负责**从调用方主动发起**交互：

- 向 service 发起一次调用并等待结果（sync）
- 发起调用但不阻塞线程（async / Future / Promise / Task）
- 发起调用并保证在连接上的顺序（asyncSeq / sequenced）
- 按 UID 或 P2P 组名定位 service
- 发出一个通知（notify），不等待返回值

### 1.2 变体命名规则（跨语言统一）

下表列出生成器在每个 API 上生成的所有变体（以函数 `Foo` 为例）：

| 变体 | 语义 | 说明 |
|------|------|------|
| `Foo` | **App 同步调用** | 按 `ABI_TARGET_APP` 定位 service，阻塞直到有结果 |
| `Foo_Async` | **App 异步调用** | 不阻塞线程，通过回调 / Future / Promise 返回结果 |
| `Foo_AsyncSequenced` | **App 异步顺序调用** | 与 `Async` 相同，但保证同一连接上按顺序 dispatch |
| `Foo_UID_Call` | **UID 同步调用** | 按目标服务的 32 字节 UID 定位，阻塞 |
| `Foo_UID_Async` | **UID 异步调用** | 同上，异步 |
| `Foo_UID_AsyncSequenced` | **UID 异步顺序调用** | 同上，且顺序保证 |
| `Foo_P2PName_Call` | **P2P 组名同步调用** | 按 P2P 组名定位，阻塞 |
| `Foo_P2PName_Async` | **P2P 组名异步调用** | 同上，异步 |
| `Foo_P2PName_AsyncSequenced` | **P2P 组名异步顺序调用** | 同上，且顺序保证 |

Procedure（无返回值）类型的 API 只生成 notify 系列变体：

| 变体 | 语义 |
|------|------|
| `Foo` | App 通知（`notify`） |
| `Foo_SequencedNotify` | App 顺序通知 |
| `Foo_UID_Notify` | UID 通知 |
| `Foo_UID_SequencedNotify` | UID 顺序通知 |
| `Foo_P2PName_Notify` | P2P 组名通知 |
| `Foo_P2PName_SequencedNotify` | P2P 组名顺序通知 |

### 1.3 关于"异步 notify"

**notify 本身就是"发出后不等待返回值"的语义**，因此从 caller 的视角看，所有 notify 调用都是非阻塞的：

- 调用 `Foo()`（App 通知）会立即返回；
- service 侧是否执行、何时执行、是否失败，caller 都不感知。

**`SequencedNotify` 的区别**：它保证同一个 LingoFuse 连接上，多个 notify 按照 caller 的调用顺序投递到 service，不会因为 worker 线程池而乱序。这是"更强的异步"，但**仍然是 fire-and-forget**。

**call 库本身不提供"异步接收 notify"的能力** —— 接收侧是 service 库的职责（`LF_RegisterNotify` + callback）。call 库只负责发送。

因此下文中：
- "**支持异步 notify**" = 支持所有 6 种 notify 变体（含 sequenced）
- "**支持异步 call**" = 支持 async / asyncSeq 变体（不阻塞线程的请求-响应模式）

---

## 2. 总览能力矩阵

### 2.1 变体数量

| 语言 | Function 变体数 | Procedure 变体数 | 异步 call | 异步 notify |
|------|:---------------:|:-----------------:|:---------:|:-----------:|
| Pascal | 15 | 6 | ✅ | ✅ |
| Python | 15 | 6 | ✅ | ✅ |
| C++ | 9 | 6 | ✅ | ✅ |
| C# | 9 | 6 | ✅ | ✅ |
| Rust | 9 | 6 | ✅ | ✅ |
| Go | 9 | 6 | ✅ | ✅ |
| Java | 9 | 6 | ✅ | ✅ |
| Node.js | 9 | 6 | ✅ | ✅ |
| TypeScript | 9 | 6 | ✅ | ✅ |
| Erlang | 6 | 6 | ✅（无 sequenced） | ✅ |
| Julia | 9 | 6 | ✅ | ✅ |
| Zig | 9 | 6 | ✅ | ✅ |
| Swift | 9 | 6 | ✅ | ✅ |
| Ruby | 9 | 6 | ✅ | ✅ |
| Fortran | **3** | **3** | ❌ | ✅（无 sequenced） |
| Dart | 9 | 6 | ✅ | ✅ |
| R | **3** | **3** | ❌ | ✅（无 sequenced） |

> **说明**
> - **Pascal** 和 **Python** 之所以是 15 种 Function 变体，是因为它们额外提供了 `_P` / `_Aio` 两套并行 API（Pascal 的 `_P` 是 nested proc / reference to，Python 的 `_Aio` 是 async/await），本质变体仍为 9 种。
> - **Erlang** 的 function 变体只有 6 种：`app_sync` / `app_async` / `uid_sync` / `uid_async` / `p2p_sync` / `p2p_async`，**无 sequenced async**。
> - **Fortran** 与 **R** 是精简版：只生成 app / UID / P2P 三种调用，**完全不支持 async / asyncSeq**。

### 2.2 平台与操作系统支持

| 语言 | 开发平台（SDK / 运行时） | Windows | Linux | macOS | 备注 |
|------|-------------------------|:-------:|:-----:|:-----:|------|
| Pascal | FPC 3.2+ / Delphi 10.4+ | ✅ | ✅ | ✅ | 需 `lingofuse_import.pas` + `Z.Core` |
| Python | CPython 3.7+ | ✅ | ✅ | ✅ | 需 `py-lingofuse` |
| C++ | C++17 编译器 | ✅ | ✅ | ✅ | 需 `LingoFuse.hpp` + `LingoFuse.c` |
| C# | .NET 6+ | ✅ | ✅ | ✅ | 需 `lingofuse` 命名空间 |
| Rust | Rust 2021 edition | ✅ | ✅ | ✅ | 需 `lingofuse` crate |
| Go | Go 1.21+ | ✅ | ✅ | ✅ | 需 `lingofuse/go` module |
| Java | JDK 22+ / Maven 3.9+ | ✅ | ✅ | ✅ | 需 `lingofuse.jar` |
| Node.js | Node.js 18+ | ✅ | ✅ | ✅ | 需 `lingofuse-js` + `koffi` |
| TypeScript | TypeScript 5.6+ / Node.js 18+ | ✅ | ✅ | ✅ | 需 `lingofuse-ts` |
| Erlang | OTP 27+ | ✅ | ✅ | ✅ | 需 `lingofuse.beam` |
| Julia | Julia 1.9+（`--threads=2`） | ✅ | ✅ | ✅ | 需 `LingoFuse` Julia 包 |
| Zig | Zig 0.17+ | ✅ | ✅ | ✅ | 需 `lingofuse` Zig 包 |
| Swift | Swift 5.9+ | ⚠️（5.9+ 有支持） | ⚠️ | ✅（主要支持） | 需 `LingoFuse` Swift 包 |
| Ruby | Ruby 3.0+ | ✅ | ✅ | ✅ | 需 `lingofuse` gem |
| Fortran | gfortran + gcc + g++ | ✅ | ✅ | ✅ | 需 `lf_fortran_mod` + `LingoFuse.c` |
| Dart | Dart 3.0+ | ✅ | ✅ | ✅ | 需 `lingofuse` Dart 包 + `lf_dart_bridge.dll` |
| R | R 4.x | ✅ | ✅ | ✅ | 需 `lingofuse` R 包 + `LingoFuse64.dll` |

> **Swift 说明**：Swift 5.9+ 官方提供 Windows 工具链，但 `LingoFuse` Swift 包当前主要在 macOS 与 Linux 上验证；Windows 建议以 C++ / C# 作为替代。

### 2.3 所有语言共用的运行时依赖

不论使用哪种语言，运行期都至少需要：

| 文件 | 作用 |
|------|------|
| `LingoFuse64.dll`（Windows）/ `liblingofuse.so`（Linux）/ `liblingofuse.dylib`（macOS） | LingoFuse 核心运行时 |
| `z_ipc_*.dll` / `libz_ipc_*.so` | IPC 传输插件（loopback 端点必需） |

各语言的绑定包（`.whl` / `.gem` / `.crate` / `.jar` / `.dll` FFI 桥等）都是上述运行时的**包装**。

---

## 3. 各语言详细接入

### 3.1 Pascal

**Call 库文件**: `<Unit>_abi_call_unit.pas`

**支持的变体**

Function（15 种）：
- `Foo`
- `Foo_Async` / `Foo_Async_P`
- `Foo_AsyncSequenced` / `Foo_AsyncSequenced_P`
- `Foo_UID_Call`
- `Foo_UID_Async` / `Foo_UID_Async_P`
- `Foo_UID_AsyncSequenced` / `Foo_UID_AsyncSequenced_P`
- `Foo_P2PName_Call`
- `Foo_P2PName_Async` / `Foo_P2PName_Async_P`
- `Foo_P2PName_AsyncSequenced` / `Foo_P2PName_AsyncSequenced_P`

Procedure（6 种）：
- `Foo`
- `Foo_SequencedNotify`
- `Foo_UID_Notify`
- `Foo_UID_SequencedNotify`
- `Foo_P2PName_Notify`
- `Foo_P2PName_SequencedNotify`

**开发平台**

| 项目 | 要求 |
|------|------|
| 编译器 | Free Pascal 3.2+ 或 Delphi 10.4+ |
| 语言模式 | Delphi 模式（`{$mode delphi}`） |
| 源码编码 | UTF-8（`{$CODEPAGE UTF8}`） |

**操作系统**: Windows / Linux / macOS。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `lingofuse_import.pas` | `-Fu<dir-with-lingofuse_import.pas>` |
| `Z.Core` | `-Fu<dir-with-Z.Core.pas>` |
| 运行时 DLL / SO / DYLIB | 放可执行文件同目录或 loader search path |

**接入代码**

```pascal
uses
  <Unit>_abi_call_unit;

var
  Result: Integer;
begin
  ABI_Timeout := 5000;
  try
    Result := Foo(10, 20);                                   // App 同步
    Result := Foo_UID_Call(MyUid, 10, 20);                   // UID 同步
    Result := Foo_P2PName_Call('my_p2p_group', 10, 20);      // P2P 同步
  except
    on E: EABI_RemoteError do
      Writeln('remote error: ', E.Message);
  end;
end;
```

**异步调用（method 回调）**

```pascal
type
  TFooHandler = class
  public
    procedure OnSuccess(const Value: Integer);
    procedure OnError(const ErrorMsg: string; Code: Integer);
  end;

var
  H: TFooHandler;
begin
  H := TFooHandler.Create;
  try
    Foo_Async(10, 20, H.OnSuccess, H.OnError);
  finally
    H.Free;
  end;
end;
```

**异步调用（nested proc 回调）**

```pascal
var
  Done: Boolean = False;
begin
  Foo_Async_P(10, 20,
    procedure(const Value: Integer)
    begin
      Done := True;
    end,
    procedure(const ErrorMsg: string; Code: Integer)
    begin
      Done := True;
    end);
end;
```

**注意事项**

- **`_M` 与 `_P` 的区别**：`_M` 是 object method（`of object`），`_P` 是 nested proc / reference to。FPC 和 Delphi 都支持，选择哪种取决于回调是否捕获上下文。
- **回调线程**：回调在 worker 线程执行，**不要**在回调内调用 `LF_Call` / `LF_Notify`（会死锁），也**不要**在回调内操作 UI（需 `TThread.Synchronize`）。
- **超时**：`ABI_Timeout` 是全局变量（unit 级），默认 5000 ms。
- **错误处理**：同步调用失败抛 `EABI_RemoteError`；异步调用通过 `OnError` 回调传递。

---

### 3.2 Python

**Call 库文件**: `<Unit>_abi_call.py`

**支持的变体**

Function（15 种）：
- `Foo`（同步，返回 `int` / `float` / `str`）
- `Foo_UID_Call`、`Foo_P2PName_Call`（同步）
- `Foo_Async`、`Foo_AsyncSequenced`（返回 `CallFuture`）
- `Foo_Aio`、`Foo_Sequenced_Aio`（`async def`）
- `Foo_UID_Async`、`Foo_UID_AsyncSequenced`、`Foo_UID_Aio`、`Foo_UID_Sequenced_Aio`
- `Foo_P2PName_Async`、`Foo_P2PName_AsyncSequenced`、`Foo_P2PName_Aio`、`Foo_P2PName_Sequenced_Aio`

Procedure（6 种）：
- `Foo`
- `Foo_SequencedNotify`
- `Foo_UID_Notify`
- `Foo_UID_SequencedNotify`
- `Foo_P2PName_Notify`
- `Foo_P2PName_SequencedNotify`

**开发平台**

| 项目 | 要求 |
|------|------|
| Python | CPython 3.7+（`asyncio` 需要 3.7+） |
| 可选依赖 | 无（`async_support` 内部实现） |

**操作系统**: Windows / Linux / macOS（CPython 支持的所有平台）。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `lingofuse` Python 包 | `pip install py-lingofuse` 或 `PYTHONPATH=<v3>/src` |

**接入代码**

```python
from lingofuse._lf_native import (
    LF_ResetPrepare, LF_PrepareClient, LF_PrepareDone,
    LF_ExitMainThread, LF_Shutdown,
)
from lingofuse.lf_io import cstr
import <Unit>_abi_call as abi

LF_ResetPrepare()
LF_PrepareClient(cstr("ipc:<Unit>_abi"), None)
if LF_PrepareDone() != 1:
    raise SystemExit(1)

try:
    abi.ABI_TIMEOUT = 5000

    # 同步 App 调用
    print(abi.Foo(10, 20))

    # 同步 UID / P2P 调用
    print(abi.Foo_UID_Call(my_uid_bytes, 10, 20))
    print(abi.Foo_P2PName_Call("my_p2p_group", 10, 20))

    # 异步 Future
    fut = abi.Foo_Async(10, 20)
    print(fut.result(timeout=5.0))

    # async/await
    import asyncio
    print(asyncio.run(abi.Foo_Aio(10, 20)))

    # 顺序通知
    abi.Foo_SequencedNotify(10, 20)
finally:
    LF_ExitMainThread()
    LF_Shutdown()
```

**注意事项**

- **`Foo_Async` 返回值**：`CallFuture`，支持 `.result(timeout=)`、`.add_done_callback(fn)`、`.cancel()`。
- **`Foo_Aio`**：`async def`，必须在 `asyncio.run()` 或已运行的 event loop 内 await。
- **`on_result` 回调**：`Foo_Async(..., on_result=fn, user_data=ud)` 允许回调式使用，`fn(result, error, user_data)`；不传 `on_result` 时返回 Future。
- **超时**：`abi.ABI_TIMEOUT`（模块级变量），0 表示不超时。
- **UID 类型**：`bytes`（32 字节）、hex 字符串（64 字符）或 `{bytes: Uint8Array(32)}` 形式（由 `normalize_uid` 处理）。
- **Python GIL**：异步回调在 `async_support` 的线程池中执行，回调内不要做阻塞 IO；`asyncio.run` 在非主线程执行时需要事件循环策略。

---

### 3.3 C++

**Call 库文件**: `<Unit>_abi_call.hpp` + `<Unit>_abi_call.cpp`

**支持的变体**

Function（9 种）：
- `Foo`（同步）
- `Foo_Async`、`Foo_AsyncSequenced`
- `Foo_UID_Call`、`Foo_UID_Async`、`Foo_UID_AsyncSequenced`
- `Foo_P2PName_Call`、`Foo_P2PName_Async`、`Foo_P2PName_AsyncSequenced`

Procedure（6 种）：
- `Foo`
- `Foo_SequencedNotify`
- `Foo_UID_Notify`
- `Foo_UID_SequencedNotify`
- `Foo_P2PName_Notify`
- `Foo_P2PName_SequencedNotify`

**开发平台**

| 项目 | 要求 |
|------|------|
| C++ 标准 | C++17 |
| 编译器 | MSVC 2019+ / g++ 9+ / clang++ 10+ |
| 可选构建系统 | CMake 3.15+ |

**操作系统**: Windows / Linux / macOS。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `LingoFuse.hpp` / `lf_io.hpp` | `-I<dir-with-headers>` |
| `LingoFuse.c` | 编译进项目（CMake 里作为 `lingofuse_c_wrapper` 静态库） |
| 运行时 DLL / SO / DYLIB | 放可执行文件同目录，或 `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH` / `PATH` |

**接入代码**

```cpp
#include "<Unit>_abi_call.hpp"
#include "LingoFuse.hpp"

int main() {
    if (LF_LoadLibrary() != 1) {
        std::fprintf(stderr, "[FATAL] LF_LoadLibrary failed\n");
        return 1;
    }

    <Unit>_abi::ABI_TargetApp = "<Unit>_abi";
    <Unit>_abi::ABI_Timeout   = 5000;

    try {
        // 同步 App 调用
        auto v = <Unit>_abi::Foo(10, 20);

        // 同步 UID / P2P 调用
        std::array<std::uint8_t, 32> uid = {/* 32 bytes */};
        auto u = <Unit>_abi::Foo_UID_Call(uid, 10, 20);
        auto p = <Unit>_abi::Foo_P2PName_Call("my_p2p_group", 10, 20);

        // 异步
        <Unit>_abi::Foo_Async(10, 20, [](lingofuse::AsyncResult r) {
            if (r.err) {
                std::printf("[FAIL] %s\n", r.err->what());
            } else {
                // r.value 是 DataHandle，需要解码
            }
        });
    } catch (const <Unit>_abi::EABI_RemoteError& e) {
        std::fprintf(stderr, "remote error: %s\n", e.what());
    }

    LF_FreeLibrary();
    return 0;
}
```

**CMake 集成**

```cmake
cmake_minimum_required(VERSION 3.15)
project(my_app LANGUAGES CXX C)
set(CMAKE_CXX_STANDARD 17)

find_package(Threads REQUIRED)

# 编译 C 包装
add_library(lingofuse_c_wrapper STATIC
    ${LINGOFUSE_CPP_DIR}/LingoFuse.c)
target_include_directories(lingofuse_c_wrapper PUBLIC ${LINGOFUSE_CPP_DIR})

# 编译 call 库
add_library(<Unit>_abi_call STATIC <Unit>_abi_call.cpp)
target_include_directories(<Unit>_abi_call PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(<Unit>_abi_call PUBLIC lingofuse_c_wrapper Threads::Threads)

# 你的应用
add_executable(my_app main.cpp)
target_link_libraries(my_app PRIVATE <Unit>_abi_call)
```

**注意事项**

- **`LF_LoadLibrary()` 必须先调用**：C++ 侧不自动加载运行时；返回 1 表示成功。
- **MSVC**：必须加 `/utf-8`，否则 API 描述字符串的编码不对。
- **`EABI_RemoteError`**：同步调用失败时抛出，包含 `what()`。
- **`std::function<void(lingofuse::AsyncResult)>`**：异步回调签名；`AsyncResult` 内含 `err`（`std::optional<std::string>`）与 `value`（`DataHandle`）。
- **UID 类型**：`std::array<std::uint8_t, 32>`。
- **回调线程**：在 worker 线程执行；回调内不做阻塞 LingoFuse 调用。

---

### 3.4 C#

**Call 库文件**: `<Unit>_abi_call.cs`

**支持的变体**

Function（9 种）：
- `ABI.Foo(...)`（同步）
- `ABI.Foo_Async(...)`（`Task<T>`）
- `ABI.Foo_AsyncSequenced(...)`（`Task<T>`）
- `ABI.Foo_UID_Call(...)`、`ABI.Foo_UID_Async(...)`、`ABI.Foo_UID_AsyncSequenced(...)`
- `ABI.Foo_P2PName_Call(...)`、`ABI.Foo_P2PName_Async(...)`、`ABI.Foo_P2PName_AsyncSequenced(...)`

Procedure（6 种）：
- `ABI.Foo(...)`
- `ABI.Foo_SequencedNotify(...)`
- `ABI.Foo_UID_Notify(...)`
- `ABI.Foo_UID_SequencedNotify(...)`
- `ABI.Foo_P2PName_Notify(...)`
- `ABI.Foo_P2PName_SequencedNotify(...)`

**开发平台**

| 项目 | 要求 |
|------|------|
| .NET | .NET 6+（`Task<T>` / `async/await`） |
| 语言 | C# 10+ |
| 项目类型 | 任意（Console / WPF / WinForms / ASP.NET Core / MAUI） |

**操作系统**: Windows / Linux / macOS（.NET Core 支持的所有平台）。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `lingofuse` 命名空间 | 拷贝 `<Unit>_abi_call.cs` 到项目，`using lingofuse;` |
| 运行时 DLL / SO / DYLIB | 放 `dotnet run` 工作目录，或 `DLLImportResolver` 可寻址处 |

**接入代码**

```csharp
using System;
using System.Threading.Tasks;
using lingofuse;
using <Unit>_abi_call;

class Program
{
    static async Task Main()
    {
        ABI.TargetApp = "<Unit>_abi";
        ABI.Timeout   = 5000;

        // 同步 App 调用
        int v = ABI.Foo(10, 20);

        // 同步 UID / P2P
        var uid = P2PUid.FromBytes(myUidBytes);
        int u = ABI.Foo_UID_Call(uid, 10, 20);
        int p = ABI.Foo_P2PName_Call("my_p2p_group", 10, 20);

        // 异步（Task）
        int a  = await ABI.Foo_Async(10, 20);
        int as_ = await ABI.Foo_AsyncSequenced(10, 20);

        // 异步 UID
        int au = await ABI.Foo_UID_Async(uid, 10, 20);

        // notify
        ABI.Foo(10, 20);                      // App notify
        ABI.Foo_SequencedNotify(10, 20);
        ABI.Foo_UID_Notify(uid, 10, 20);
        ABI.Foo_P2PName_Notify("my_p2p_group", 10, 20);
    }
}
```

**注意事项**

- **`ABI.TargetApp` / `ABI.Timeout`**：`ABI` 类的静态字段，全局生效；修改后所有后续调用都受影响。
- **`P2PUid`**：32 字节 UID 的封装类型，支持 `FromBytes` / `ToByteArray` / `IsEmpty`。
- **异步实现**：`Foo_Async` 返回 `Task<T>`，内部基于 `TaskCompletionSource`；`await` 可直接使用。
- **`DllImportResolver`**：自动按平台选择 `LingoFuse64.dll` / `LingoFuse32.dll` / `liblingofuse.so` / `liblingofuse.dylib`。
- **回调线程**：C# 的 async 回调内部已通过 `TaskCompletionSource` 编组到线程池；后续 `.ConfigureAwait(false)` 可避免死锁。

---

### 3.5 Rust

**Call 库文件**: `<Unit>_abi_call.rs`

**支持的变体**

Function（9 种）：
- `Foo(...)`（同步，返回 `Result<T, Error>`）
- `Foo_Async(...)`、`Foo_AsyncSequenced(...)`
- `Foo_UID_Call(...)`、`Foo_UID_Async(...)`、`Foo_UID_AsyncSequenced(...)`
- `Foo_P2PName_Call(...)`、`Foo_P2PName_Async(...)`、`Foo_P2PName_AsyncSequenced(...)`

Procedure（6 种）：
- `Foo(...)`
- `Foo_SequencedNotify(...)`
- `Foo_UID_Notify(...)`
- `Foo_UID_SequencedNotify(...)`
- `Foo_P2PName_Notify(...)`
- `Foo_P2PName_SequencedNotify(...)`

**开发平台**

| 项目 | 要求 |
|------|------|
| Rust | 2021 edition |
| 工具链 | rustc 1.70+ / cargo |

**操作系统**: Windows / Linux / macOS（Rust 支持的所有平台）。

**依赖**

```toml
[dependencies]
lingofuse = { path = "<LingoFuse>/rust" }
```

**接入代码**

```rust
use <Unit>_abi::call;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    call::ABI_TARGET_APP
        .write()
        .unwrap()
        .clone_from(&"<Unit>_abi".to_string());
    call::ABI_TIMEOUT.store(5000, std::sync::atomic::Ordering::SeqCst);

    // 同步 App 调用
    let v: i32 = call::Foo(10, 20)?;

    // 同步 UID / P2P
    let uid = lingofuse::uid::Uid::from_bytes(my_uid_bytes);
    let u: i32 = call::Foo_UID_Call(uid, 10, 20)?;
    let p: i32 = call::Foo_P2PName_Call("my_p2p_group", 10, 20)?;

    // 异步
    let (tx, rx) = std::sync::mpsc::channel();
    call::Foo_Async(10, 20, move |r| { let _ = tx.send(r); })?;
    let a = rx.recv_timeout(std::time::Duration::from_secs(10))??;

    // notify
    call::Foo(10, 20)?;                              // App notify
    call::Foo_SequencedNotify(10, 20)?;
    call::Foo_UID_Notify(uid, 10, 20)?;
    call::Foo_P2PName_Notify("my_p2p_group", 10, 20)?;

    Ok(())
}
```

**注意事项**

- **`ABI_TARGET_APP` / `ABI_TIMEOUT`**：`RwLock<&'static str>` / `AtomicU64` 静态变量。
- **错误类型**：`Result<T, lingofuse::error::Error>`；`Error` 内含 `ErrorCode` 枚举（`CallFailed` / `ReadFailed` / `NullHandle` / `Timeout` 等）。
- **异步签名**：`FnOnce(Result<T, Error>) + Send + 'static`；回调在 worker 线程执行。
- **`_lf_async_impl` 模块**：处理 UID / P2PName 的 asyncSeq；如果异步回调内需要持有 Rust 状态，确保 `Send`。
- **panic 安全**：库内部对回调做了 `catch_unwind`，但建议你的回调也不要 panic。

---

### 3.6 Go

**Call 库文件**: `<Unit>_abi_call.go`

**支持的变体**

Function（9 种）：
- `Foo(...) (T, error)`（同步）
- `Foo_Async(...)`、`Foo_AsyncSequenced(...)`（通过 `onResult func(T, error)` 回调）
- `Foo_UID_Call(...)`、`Foo_UID_Async(...)`、`Foo_UID_AsyncSequenced(...)`
- `Foo_P2PName_Call(...)`、`Foo_P2PName_Async(...)`、`Foo_P2PName_AsyncSequenced(...)`

Procedure（6 种）：
- `Foo(...) error`
- `Foo_SequencedNotify(...) error`
- `Foo_UID_Notify(...) error`
- `Foo_UID_SequencedNotify(...) error`
- `Foo_P2PName_Notify(...) error`
- `Foo_P2PName_SequencedNotify(...) error`

**开发平台**

| 项目 | 要求 |
|------|------|
| Go | 1.21+ |
| Module | `github.com/PassByYou888/LingoFuse/go` |

**操作系统**: Windows / Linux / macOS。

**依赖**

```go
require github.com/PassByYou888/LingoFuse/go v0.0.0
replace github.com/PassByYou888/LingoFuse/go => <path-to-lingofuse-go>
```

**接入代码**

```go
package main

import (
    "fmt"
    abi "<Unit>_abi"
    "github.com/PassByYou888/LingoFuse/go/sys"
)

func main() {
    if err := sys.LoadLibrary(); err != nil {
        panic(err)
    }
    defer sys.FreeLibrary()

    abi.ABI_TargetApp = "<Unit>_abi"
    abi.ABI_Timeout   = 5000 * time.Millisecond

    // 同步 App 调用
    v, err := abi.Foo(10, 20)
    if err != nil {
        fmt.Println("error:", err)
    }

    // 同步 UID / P2P
    u, _ := abi.Foo_UID_Call(uid, 10, 20)
    p, _ := abi.Foo_P2PName_Call("my_p2p_group", 10, 20)

    // 异步
    ch := make(chan int, 1)
    abi.Foo_Async(10, 20, func(v int, err error) {
        if err == nil {
            ch <- v
        }
    })
    result := <-ch

    // notify
    _ = abi.Foo(10, 20)                            // App notify
    _ = abi.Foo_SequencedNotify(10, 20)
    _ = abi.Foo_UID_Notify(uid, 10, 20)
    _ = abi.Foo_P2PName_Notify("my_p2p_group", 10, 20)

    _ = result
}
```

**注意事项**

- **`sys.LoadLibrary()` 必须先调用**：Go 侧不自动加载运行时。
- **`ABI_Timeout` 是 `time.Duration`**：默认 5000 ms，可用 `5*time.Second` 或 `5000*time.Millisecond`。
- **`sys.TP2P_UID`**：32 字节 UID 类型，定义为 `[32]byte` 封装。
- **异步回调**：`onResult func(T, error)` 在 Go worker goroutine 中执行；不要在里面阻塞或做长时间工作。
- **`panicToError`**：库内部会捕获 `internal_call` 的 panic 并转为 `error`。

---

### 3.7 Java

**Call 库文件**: `<Unit>AbiCall.java`

**支持的变体**

Function（9 种）：
- `<Unit>AbiCall.callFoo(...)`（同步）
- `<Unit>AbiCall.callFooAsync(...)`
- `<Unit>AbiCall.callFooSequencedAsync(...)`
- `<Unit>AbiCall.callFooByUid(...)`、`callFooAsyncByUid(...)`、`callFooSequencedAsyncByUid(...)`
- `<Unit>AbiCall.callFooByP2PName(...)`、`callFooAsyncByP2PName(...)`、`callFooSequencedAsyncByP2PName(...)`

Procedure（6 种）：
- `<Unit>AbiCall.notifyFoo(...)`
- `notifyFooSequenced(...)`
- `notifyFooByUid(...)`、`notifyFooSequencedByUid(...)`
- `notifyFooByP2PName(...)`、`notifyFooSequencedByP2PName(...)`

**开发平台**

| 项目 | 要求 |
|------|------|
| JDK | 22+（`maven.compiler.release=22`） |
| 构建 | Maven 3.9+ |
| 依赖 | `lingofuse.jar` + `jackson-databind` |

**操作系统**: Windows / Linux / macOS（JVM 支持的所有平台）。

**依赖**

```xml
<dependency>
    <groupId>lingofuse</groupId>
    <artifactId>lingofuse</artifactId>
    <version>1.0.0</version>
    <scope>system</scope>
    <systemPath>${project.basedir}/lib/lingofuse.jar</systemPath>
</dependency>
```

**接入代码**

```java
import lingofuse.DataHandle;
import lingofuse.Framework;
import lingofuse.async.TypedAsyncResultHandler;
import <Unit>_abi.<Unit>AbiCall;

public class Main {
    public static void main(String[] args) throws Exception {
        lingofuse.ffi.LibraryLoader.selectPlatformFileName();

        <Unit>AbiCall.ABI_TARGET_APP = "<Unit>_abi";
        <Unit>AbiCall.ABI_TIMEOUT    = 5000L;

        // 同步 App 调用
        int v = <Unit>AbiCall.callFoo(10, 20);

        // 同步 UID / P2P
        byte[] uid = myUidBytes;
        int u = <Unit>AbiCall.callFooByUid(uid, 10, 20);
        int p = <Unit>AbiCall.callFooByP2PName("my_p2p_group", 10, 20);

        // 异步（回调式）
        boolean dispatched = <Unit>AbiCall.callFooAsync(10, 20,
            new TypedAsyncResultHandler<Integer>() {
                @Override
                public void onResult(Integer value, Throwable err) {
                    if (err != null) {
                        System.err.println("error: " + err.getMessage());
                    } else {
                        System.out.println("value: " + value);
                    }
                }
            });

        // notify
        <Unit>AbiCall.notifyFoo(10, 20);
        <Unit>AbiCall.notifyFooSequenced(10, 20);
        <Unit>AbiCall.notifyFooByUid(uid, 10, 20);
        <Unit>AbiCall.notifyFooByP2PName("my_p2p_group", 10, 20);
    }
}
```

**注意事项**

- **`LibraryLoader.selectPlatformFileName()`** 必须先调用，否则 `System.loadLibrary` 找不到运行时。
- **`ABI_TARGET_APP` / `ABI_TIMEOUT`**：`<Unit>AbiCall` 的静态字段。
- **异步签名**：`TypedAsyncResultHandler<T>.onResult(T value, Throwable err)`；`callFooAsync` 返回 `boolean`（是否成功 dispatch）。
- **`EABIRemoteError`**：同步调用失败时抛出；`getCause()` 可拿到底层异常。
- **Java 22 特性**：`ABI.ABI_ERR_*` 常量、`switch` 表达式等；如果需要 Java 21，改 `pom.xml` 的 `maven.compiler.release`。

---

### 3.8 Node.js

**Call 库文件**: `<Unit>_abi_call.js`

**支持的变体**

Function（9 种）：
- `<module>.Foo(...)`（同步）
- `<module>.FooAsync(...)`（`Promise<T>`）
- `<module>.FooSequenced(...)`（`Promise<T>`）
- `<module>.FooByUid(...)`、`FooByUidAsync(...)`、`FooByUidSequenced(...)`
- `<module>.FooByP2PName(...)`、`FooByP2PNameAsync(...)`、`FooByP2PNameSequenced(...)`

Procedure（6 种）：
- `<module>.Foo(...)`
- `<module>.FooSequenced(...)`
- `<module>.FooByUid(...)`、`FooByUidSequenced(...)`
- `<module>.FooByP2PName(...)`、`FooByP2PNameSequenced(...)`

**开发平台**

| 项目 | 要求 |
|------|------|
| Node.js | 18+ |
| FFI | `koffi`（`lingofuse-js` 依赖） |

**操作系统**: Windows / Linux / macOS。

**依赖**

```bash
npm install lingofuse-js
# 或通过 setup_node_tests.ps1 自动安装
```

**接入代码**

```javascript
'use strict';
const lf = require('lingofuse-js');
const abi = require('./<Unit>_abi_call.js');

lf.loadLibrary();
lf.framework.setOption('Quiet', 'True');

abi.ABI_TargetApp = '<Unit>_abi';
abi.ABI_Timeout   = 5000;

(async () => {
    // 同步 App 调用
    const v = abi.Foo(10, 20);

    // 同步 UID / P2P
    const u = abi.FooByUid(uidBytes, 10, 20);
    const p = abi.FooByP2PName('my_p2p_group', 10, 20);

    // 异步（Promise）
    const a  = await abi.FooAsync(10, 20);
    const as_ = await abi.FooSequenced(10, 20);

    // 异步 UID
    const au = await abi.FooByUidAsync(uidBytes, 10, 20);

    // notify
    abi.Foo(10, 20);
    abi.FooSequenced(10, 20);
    abi.FooByUid(uidBytes, 10, 20);
    abi.FooByP2PName('my_p2p_group', 10, 20);

    // 关闭
    lf.AsyncBridge.shutdownInstance();
    lf.framework.exitMainThread();
    lf.framework.shutdown();
})();
```

**注意事项**

- **`lf.loadLibrary()`**：显式加载运行时；失败抛异常。
- **`ABI_TargetApp` / `ABI_Timeout`**：模块导出的 getter/setter，动态修改全局值。
- **`ABI_Timeout` 是 number**：单位 ms。
- **UID 类型**：`Uint8Array(32)`、64 字符 hex string、或 `{bytes: Uint8Array(32)}` 对象；由 `_wrapUid` 归一化。
- **异步错误**：Promise reject 时，错误会被包成 `Error`；`Error.message` 是 service 返回的错误字符串。
- **`AsyncBridge.shutdownInstance()`**：Node.js 进程退出前必须调用，否则 worker 线程会被挂住。

---

### 3.9 TypeScript

**Call 库文件**: `<Unit>_abi_call.ts`

**支持的变体**

与 Node.js 完全一致（文件名与 API 名一致，仅类型更严格）。

Function（9 种）：
- `<module>.Foo(...)`（`number` / `bigint` / `string`）
- `<module>.FooAsync(...)`（`CallPromise<T>`）
- `<module>.FooSequenced(...)`（`CallPromise<T>`）
- `<module>.FooByUid(...)`、`FooByUidAsync(...)`、`FooByUidSequenced(...)`
- `<module>.FooByP2PName(...)`、`FooByP2PNameAsync(...)`、`FooByP2PNameSequenced(...)`

Procedure（6 种）：
- `<module>.Foo(...)`
- `<module>.FooSequenced(...)`
- `<module>.FooByUid(...)`、`FooByUidSequenced(...)`
- `<module>.FooByP2PName(...)`、`FooByP2PNameSequenced(...)`

**开发平台**

| 项目 | 要求 |
|------|------|
| Node.js | 18+ |
| TypeScript | 5.6+ |
| 包管理 | `lingofuse-ts` |

**操作系统**: Windows / Linux / macOS。

**依赖**

```bash
npm install lingofuse-ts
# 或通过 setup_ts_tests.ps1 自动安装与自动链接
```

**接入代码**

```typescript
import * as lf from "lingofuse-ts";
import * as abi from "./<Unit>_abi_call";

lf.loadLibrary();
lf.framework.setOption("Quiet", "True");

abi.ABI.TargetApp = "<Unit>_abi";
abi.ABI.Timeout   = 5000;

async function main() {
    // 同步 App 调用
    const v: number = abi.Foo(10, 20);

    // 同步 UID / P2P
    const u = abi.FooByUid(uidBytes, 10, 20);
    const p = abi.FooByP2PName("my_p2p_group", 10, 20);

    // 异步（CallPromise）
    const a  = await abi.FooAsync(10, 20);
    const as_ = await abi.FooSequenced(10, 20);

    // notify
    abi.Foo(10, 20);
    abi.FooSequenced(10, 20);
    abi.FooByUid(uidBytes, 10, 20);
    abi.FooByP2PName("my_p2p_group", 10, 20);

    lf.AsyncBridge.shutdownInstance();
    lf.framework.exitMainThread();
    lf.framework.shutdown();
}

main().catch(e => { console.error(e); process.exit(1); });
```

**注意事项**

- **`ABI.TargetApp` / `ABI.Timeout`**：`ABI` 对象的 setter，动态生效。
- **`CallPromise<T>` 类型**：`lingofuse-ts` 导出的 `Promise<T>` 子类型，带超时和取消。
- **`bigint` 支持**：`int64` / `uint64` 返回 `bigint`；TypeScript 编译目标是 `ES2020+`。
- **`tsconfig.json`**：`module: "commonjs"`，`strict: true`；否则 `lingofuse-ts` 的 CommonJS 模块可能加载失败。

---

### 3.10 Erlang

**Call 库文件**: `<Unit>_abi_call.erl`

**支持的变体**

Function（6 种）：
- `Foo(App)`（同步 App）
- `Foo_async(App, Callback)`（异步 App，无 sequenced）
- `Foo_uid(Uid)` / `Foo_uid_async(Uid, Callback)`
- `Foo_p2p(P2p)` / `Foo_p2p_async(P2p, Callback)`

Procedure（6 种）：
- `Foo(App)`、`Foo_seq(App)`（顺序通知）
- `Foo_uid(Uid)`、`Foo_uid_seq(Uid)`
- `Foo_p2p(P2p)`、`Foo_p2p_seq(P2p)`

**开发平台**

| 项目 | 要求 |
|------|------|
| Erlang/OTP | 27+（`erl` / `erlc` / `escript`） |
| 依赖模块 | `lingofuse.beam`（在 `LINGOFUSE_EBIN` 中） |

**操作系统**: Windows / Linux / macOS（BEAM VM 支持的所有平台）。

**依赖**

- `lingofuse.beam` 所在目录加入 `-pa`。

**接入代码**

```erlang
%% 同步 App 调用
case '<Unit>_abi_call':'Foo'(<<>>, 10, 20) of
    {ok, V} -> io:format("result: ~p~n", [V]);
    {error, Reason} -> io:format("error: ~p~n", [Reason])
end.

%% 异步 App 调用
Self = self(),
'<Unit>_abi_call':'Foo_async'(<<>>, 10, 20, fun(R) -> Self ! {result, R} end),
receive
    {result, {ok, V}} -> io:format("async result: ~p~n", [V]);
    {result, {error, Reason}} -> io:format("async error: ~p~n", [Reason])
after 5000 -> io:format("timeout~n")
end.

%% 同步 UID / P2P
{ok, U} = '<Unit>_abi_call':'Foo_uid'(Uid, 10, 20),
{ok, P} = '<Unit>_abi_call':'Foo_p2p'(P2p, 10, 20).

%% notify
ok = '<Unit>_abi_call':'Foo'(<<>>, 10, 20).
ok = '<Unit>_abi_call':'Foo_seq'(<<>>, 10, 20).
ok = '<Unit>_abi_call':'Foo_uid'(Uid, 10, 20).
ok = '<Unit>_abi_call':'Foo_p2p'(P2p, 10, 20).
```

**注意事项**

- **Erlang 的 atom 引用**：函数名用单引号包裹（`'Foo'` / `'Foo_async'` / `'Foo_uid'`），因为生成器用 `ErlangQuotedAtom` 包装。
- **返回值**：`{ok, V}` 或 `{error, Reason}`；Reason 可能是 `timeout`、`{decode_error, Bin}`、`{unexpected_status, S}`。
- **异步支持**：仅 `_async` / `_uid_async` / `_p2p_async` 三种，**无 sequenced async**。
- **notify**：`_seq` 后缀表示顺序通知；其余为普通通知。全部 6 种变体均支持。
- **超时**：`?ABI_TIMEOUT_MS` 宏，默认 5000 ms；`lf_do_call_async` 内部有 `after ?ABI_TIMEOUT_MS` 超时保护。
- **进程模型**：异步回调在 `spawn` 出的 Collector 进程中执行；不要在回调内 `receive` 阻塞消息。

---

### 3.11 Julia

**Call 库文件**: `<Unit>_abi_call.jl`

**支持的变体**

Function（9 种）：
- `ApiName(...)`（同步）
- `ApiName_Async(...)`、`ApiName_AsyncSequenced(...)`（返回 `LF.Future`）
- `ApiName_UID_Call(...)`、`ApiName_UID_Async(...)`、`ApiName_UID_AsyncSequenced(...)`
- `ApiName_P2PName_Call(...)`、`ApiName_P2PName_Async(...)`、`ApiName_P2PName_AsyncSequenced(...)`

Procedure（6 种）：
- `ApiName(...)`
- `ApiName_SequencedNotify(...)`
- `ApiName_UID_Notify(...)`、`ApiName_UID_SequencedNotify(...)`
- `ApiName_P2PName_Notify(...)`、`ApiName_P2PName_SequencedNotify(...)`

**开发平台**

| 项目 | 要求 |
|------|------|
| Julia | 1.9+ |
| 线程 | 必须 `--threads=2`（异步依赖多线程） |

**操作系统**: Windows / Linux / macOS。

**依赖**

- `LingoFuse` Julia 包（`Pkg.develop(path="<LingoFuse>/julia")`）。

**接入代码**

```julia
import LingoFuse
const LF = LingoFuse
include("<Unit>_abi_call.jl")
const abi = <Unit>_abi_call

abi.ABI_TargetApp[] = "<Unit>_abi"
abi.ABI_Timeout[]   = 5000

# 同步 App 调用
v = abi.Foo(10, 20)

# 同步 UID / P2P
u = abi.Foo_UID_Call(uid, 10, 20)
p = abi.Foo_P2PName_Call("my_p2p_group", 10, 20)

# 异步（返回 LF.Future）
f = abi.Foo_Async(10, 20)
v_async = f.value(timeout_ms=5000)

# 异步 UID
f_uid = abi.Foo_UID_Async(uid, 10, 20)

# notify
abi.Foo(10, 20)
abi.Foo_SequencedNotify(10, 20)
abi.Foo_UID_Notify(uid, 10, 20)
abi.Foo_P2PName_Notify("my_p2p_group", 10, 20)
```

**注意事项**

- **`--threads=2` 强制要求**：异步依赖 `Threads.@spawn`；启动 `julia` 时必须加 `--threads=2`。
- **`ABI_TargetApp` / `ABI_Timeout`**：`Ref{String}` / `Ref{Int}`，需用 `[]` 赋值（`abi.ABI_TargetApp[] = "..."`）。
- **`LF.Future`**：支持 `.value(timeout_ms=...)`、`.on_result(fn)`、`.cancel()`。
- **错误类型**：`EABI_RemoteError`；`catch e` 后用 `_format_exception(e)` 拿字符串。
- **UID**：`NTuple{32, UInt8}` 元组。

---

### 3.12 Zig

**Call 库文件**: `<Unit>_abi_call.zig`

**支持的变体**

Function（9 种）：
- `ApiName(...)`（`Error!T`）
- `ApiName_async(...)`、`ApiName_async_sequenced(...)`（`Error!void`，回调式）
- `ApiName_uid(...)`、`ApiName_uid_async(...)`、`ApiName_uid_async_sequenced(...)`
- `ApiName_p2p_name(...)`、`ApiName_p2p_name_async(...)`、`ApiName_p2p_name_async_sequenced(...)`

Procedure（6 种）：
- `ApiName(...)`
- `ApiName_sequenced_notify(...)`
- `ApiName_uid_notify(...)`、`ApiName_uid_sequenced_notify(...)`
- `ApiName_p2p_name_notify(...)`、`ApiName_p2p_name_sequenced_notify(...)`

**开发平台**

| 项目 | 要求 |
|------|------|
| Zig | 0.17+ |
| 模块 | `lingofuse` Zig 包 |

**操作系统**: Windows / Linux / macOS。

**依赖**

```zig
const lf = @import("lingofuse");
```

`build.zig.zon` 中需要：

```zig
.dependencies = .{
    .lingofuse = .{ .path = "<LingofuseDir>" },
},
```

**接入代码**

```zig
const std = @import("std");
const lf = @import("lingofuse");
const call = @import("<Unit>_abi_call");

pub fn main() !void {
    call.ABI_TARGET_APP = "<Unit>_abi";
    call.ABI_TIMEOUT = 5000;

    // 同步 App 调用
    const v = try call.foo(10, 20);

    // 同步 UID / P2P
    const uid = lf.Uid.fromBytes(my_uid_bytes);
    const u = try call.foo_uid(uid, 10, 20);
    const p = try call.foo_p2p_name("my_p2p_group", 10, 20);

    // 异步（回调式）
    const Ctx = struct {
        result: ?i32 = null,
        fn onResult(self: *@This(), r: call.FooResult) void {
            switch (r) {
                .ok => |v| { self.result = v; },
                .err => |e| { std.debug.print("error: {}\n", .{e}); },
            }
        }
    };
    var ctx = Ctx{};
    try call.foo_async(10, 20, &ctx, Ctx.onResult);

    // notify
    try call.foo(10, 20);
    try call.foo_sequenced_notify(10, 20);
    try call.foo_uid_notify(uid, 10, 20);
    try call.foo_p2p_name_notify("my_p2p_group", 10, 20);
}
```

**注意事项**

- **`ABI_TARGET_APP` / `ABI_TIMEOUT`**：模块级 `pub var` 变量，可直接赋值。
- **`foo_async` 签名**：`fn foo_async(..., user_ctx: ?*anyopaque, user_handler: FooAsyncHandler) Error!void`。
- **`FooResult` 联合体**：`union(enum) { ok: T, err: lf.Error }`。
- **`lf.Error`**：包含 `CallFailed` / `ReadFailed` / `OutOfMemory` 等。
- **`lf.Uid`**：32 字节 UID 类型；`Uid.NULL` 是零 UID。
- **`foo_p2p_name` 参数类型**：`[:0]const u8`（0 结尾的字符串切片）。

---

### 3.13 Swift

**Call 库文件**: `<Unit>_abi_call.swift`

**支持的变体**

Function（9 种）：
- `Foo(...)`（`throws`）
- `Foo_Async(...)`、`Foo_AsyncSequenced(...)`（`async throws`）
- `Foo_UID_Call(...)`、`Foo_UID_Async(...)`、`Foo_UID_AsyncSequenced(...)`
- `Foo_P2PName_Call(...)`、`Foo_P2PName_Async(...)`、`Foo_P2PName_AsyncSequenced(...)`

Procedure（6 种）：
- `Foo(...)`
- `Foo_SequencedNotify(...)`
- `Foo_UID_Notify(...)`、`Foo_UID_SequencedNotify(...)`
- `Foo_P2PName_Notify(...)`、`Foo_P2PName_SequencedNotify(...)`

**开发平台**

| 项目 | 要求 |
|------|------|
| Swift | 5.9+ |
| 平台（官方支持） | macOS 12+（主要），Linux（社区验证），Windows（5.9+ 有工具链但未充分验证） |

**操作系统**: macOS（主要）/ Linux（社区）/ Windows（谨慎）。

**依赖**

- `LingoFuse` Swift 包（`Package.swift` 中 `.package(path: "<LingofuseDir>")`）。

**接入代码**

```swift
import Foundation
import LingoFuse
import <Unit>_abi_call

<Unit>ABICall.targetAppName    = "<Unit>_abi"
<Unit>ABICall.defaultTimeoutMs = 5000

// 同步 App 调用
do {
    let v = try <Unit>ABICall.Foo(10, 20)
} catch {
    print("error: \(error)")
}

// 同步 UID / P2P
let uid = Uid.fromBytes(myUidBytes)
let u = try <Unit>ABICall.Foo_UID_Call(uid, 10, 20)
let p = try <Unit>ABICall.Foo_P2PName_Call("my_p2p_group", 10, 20)

// 异步（Swift Concurrency）
Task {
    let a = try await <Unit>ABICall.Foo_Async(10, 20)
    let as_ = try await <Unit>ABICall.Foo_AsyncSequenced(10, 20)
    let au = try await <Unit>ABICall.Foo_UID_Async(uid, 10, 20)
}

// notify
try <Unit>ABICall.Foo(10, 20)
try <Unit>ABICall.Foo_SequencedNotify(10, 20)
try <Unit>ABICall.Foo_UID_Notify(uid, 10, 20)
try <Unit>ABICall.Foo_P2PName_Notify("my_p2p_group", 10, 20)
```

**注意事项**

- **`targetAppName` / `defaultTimeoutMs`**：`enum <Unit>ABICall` 的静态字段。
- **Swift Concurrency**：`Foo_Async` 是 `async throws`，使用原生 `Task` + `await`。
- **`Uid` 类型**：`LingoFuse` 包导出的 32 字节 UID 类型；`Uid.fromBytes` / `Uid.null`。
- **`LingoFuseError`**：`.callFailed(...)` / `.timeout(...)` 等；与 `Task` 的 `CancellationError` 区分。
- **Windows 支持**：官方 Swift 5.9+ 有 Windows 工具链，但 `LingoFuse` Swift 包在 Windows 上的行为未经过充分验证；生产环境建议优先 macOS / Linux，或改用 C++ / C#。

---

### 3.14 Ruby

**Call 库文件**: `<Unit>_abi_call.rb`

**支持的变体**

Function（9 种）：
- `<Unit>_abi::Call.Foo(...)`（同步）
- `<Unit>_abi::Call.Foo_async(...)`、`Foo_async_sequenced(...)`（返回 Future）
- `<Unit>_abi::Call.Foo_uid_call(...)`、`Foo_uid_async(...)`、`Foo_uid_async_sequenced(...)`
- `<Unit>_abi::Call.Foo_p2pname_call(...)`、`Foo_p2pname_async(...)`、`Foo_p2pname_async_sequenced(...)`

Procedure（6 种）：
- `<Unit>_abi::Call.Foo(...)`
- `<Unit>_abi::Call.Foo_sequenced_notify(...)`
- `<Unit>_abi::Call.Foo_uid_notify(...)`、`Foo_uid_sequenced_notify(...)`
- `<Unit>_abi::Call.Foo_p2pname_notify(...)`、`Foo_p2pname_sequenced_notify(...)`

**开发平台**

| 项目 | 要求 |
|------|------|
| Ruby | 3.0+ |
| Gem | `lingofuse` |

**操作系统**: Windows / Linux / macOS（Ruby 支持的所有平台）。

**依赖**

```bash
gem install lingofuse
# 或通过 setup_ruby_tests.ps1 建立 lib 链接
```

**接入代码**

```ruby
require 'lingofuse'
require_relative '<Unit>_abi_call'

include <Unit>_abi

LingoFuse::Options.set_opt_quiet(true)

Call::ABI_TARGET_APP = '<Unit>_abi'
Call::ABI_TIMEOUT_MS = 5000

# 同步 App 调用
v = Call.Foo(10, 20)

# 同步 UID / P2P
u = Call.Foo_uid_call(uid, 10, 20)
p = Call.Foo_p2pname_call('my_p2p_group', 10, 20)

# 异步（Future）
f = Call.Foo_async(10, 20)
v_async = f.value(timeout_ms: 5000)

# notify
Call.Foo(10, 20)
Call.Foo_sequenced_notify(10, 20)
Call.Foo_uid_notify(uid, 10, 20)
Call.Foo_p2pname_notify('my_p2p_group', 10, 20)
```

**注意事项**

- **`ABI_TARGET_APP` / `ABI_TIMEOUT_MS`**：`<Unit>_abi::Call` 模块的常量（**不是** module_function），赋值时用 `Call::ABI_TARGET_APP = ...`。
- **`async` 返回的 Future**：`AsyncSupport.run_async_with_future` 返回对象含 `value(timeout_ms:)` / `add_done_callback`。
- **`LingoFuse::CallError`**：同步调用失败抛出；包含 `.message`。
- **UID 类型**：`String`（32 字节二进制）；`safe_uid(input)` 辅助函数处理 nil。
- **模块命名空间**：`module <Unit>_abi; module Call; ... end; end`；include 后可直接 `Call.Foo`。
- **超时**：`ABI_TIMEOUT_MS` 是模块常量，不能改；如需改超时请重新生成或用 `LingoFuse::Native` 裸调用。

---

### 3.15 Fortran

**Call 库文件**: `<Unit>_abi_call.f90`

**支持的变体（精简版）**

Function（3 种）：
- `ApiName(app, [args], ret, rc)`（同步，App）
- `ApiName_UID_Call(uid, [args], ret, rc)`（同步，UID）
- `ApiName_P2PName_Call(p2p_name, [args], ret, rc)`（同步，P2P 组名）

Procedure（3 种）：
- `ApiName(app, [args], rc)`
- `ApiName_UID_Notify(uid, [args], rc)`
- `ApiName_P2PName_Notify(p2p_name, [args], rc)`

**❌ 不支持异步调用（无 async / asyncSeq）**

**❌ 不支持 sequenced notify**

**开发平台**

| 项目 | 要求 |
|------|------|
| 编译器 | gfortran 9+ + gcc 9+ + g++ 9+ |
| 模块 | `lf_fortran_mod` + `LingoFuse.c` + `lf_fortran.cpp` + `lf_fortran.h` |

**操作系统**: Windows / Linux / macOS（gfortran 支持的所有平台）。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `lf_fortran_mod.f90` | 编译进项目 |
| `LingoFuse.c` | 编译进项目 |
| `lf_fortran.cpp` | 编译进项目 |
| `LingoFuse64.dll` / `z_ipc_64.dll` | 可执行文件同目录 |

**接入代码**

```fortran
program my_app
  use iso_c_binding
  use lf_fortran_mod
  use <Unit>_abi_call
  implicit none

  integer(c_int32_t) :: rc
  integer(c_int32_t) :: v
  integer(c_int8_t) :: uid(LF_UID_BYTE_COUNT)

  call lf_load_library()

  ! 同步 App 调用
  call Foo(DEFAULT_TARGET_APP, 10_c_int32_t, 20_c_int32_t, v, rc)
  if (rc /= 0_c_int32_t) print *, 'error rc=', rc

  ! 同步 UID 调用
  call Foo_UID_Call(uid, 10_c_int32_t, 20_c_int32_t, v, rc)

  ! 同步 P2P 调用
  call Foo_P2PName_Call('my_p2p_group', 10_c_int32_t, 20_c_int32_t, v, rc)

  ! notify
  call Foo(DEFAULT_TARGET_APP, 10_c_int32_t, 20_c_int32_t, rc)
  call Foo_UID_Notify(uid, 10_c_int32_t, 20_c_int32_t, rc)
  call Foo_P2PName_Notify('my_p2p_group', 10_c_int32_t, 20_c_int32_t, rc)

  call lf_free_library()
end program
```

**注意事项**

- **`rc` 返回码**：`0` = 成功；`1` = CreateData 失败；`2` = 写入参数失败；`3` = 返回空句柄；`4` = 状态字节读取失败；`5` = 远端错误；`6` = 结果读取失败。
- **无异步**：Fortran 侧完全没有 async / callback 机制；如果需要并发，请使用多线程 Fortran（OpenMP）并在线程内调用同步接口。
- **无 sequenced notify**：notify 只生成普通变体（不保证顺序）。
- **字符串参数**：`character(len=*), intent(in)`，Fortran 内部自动转 UTF-8 + NUL。
- **字符串返回**：`character(len=:), allocatable, intent(out) :: ret`；由 Fortran 运行时自动管理生命周期。

---

### 3.16 Dart

**Call 库文件**: `<Unit>_abi_call.dart`

**支持的变体**

Function（9 种）：
- `Foo(...)`（`Future<T>`，内部通过 `Isolate.run` 包装同步调用）
- `FooAsync(..., onResult)`（callback 式）
- `FooSequenced(...)`（`Future<T>`）
- `FooByUid(...)`（`Future<T>`）、`FooByUidAsync(...)`、`FooByUidSequenced(...)`
- `FooByP2PName(...)`、`FooByP2PNameAsync(...)`、`FooByP2PNameSequenced(...)`

Procedure（6 种）：
- `FooNotify(...)`
- `FooSequencedNotify(...)`
- `FooNotifyByUid(...)`、`FooSequencedNotifyByUid(...)`
- `FooNotifyByP2PName(...)`、`FooSequencedNotifyByP2PName(...)`

**开发平台**

| 项目 | 要求 |
|------|------|
| Dart | 3.0+ |
| 桥 | `lf_dart_bridge.dll`（Windows）/ `.so` / `.dylib` |
| 包 | `lingofuse` Dart 包 |

**操作系统**: Windows / Linux / macOS（Dart VM 支持的所有平台）。

**依赖**

```yaml
dependencies:
  lingofuse:
    path: "<LingoFuseDart>"
```

**接入代码**

```dart
import 'dart:async';
import 'package:lingofuse/lingofuse.dart';
import '<Unit>_abi_call.dart' as abi;

Future<void> main() async {
  await BridgeHost.start();
  Framework.setOptQuiet(true);

  abi.ABI_TARGET_APP = '<Unit>_abi';
  abi.ABI_TIMEOUT_MS = 5000;

  // 同步包装为 Future（Isolate.run）
  final v = await abi.Foo(10, 20);

  // 顺序调用
  final as_ = await abi.FooSequenced(10, 20);

  // callback 式异步
  await _waitAsync('FooAsync', (finish) {
    abi.FooAsync(10, 20, finish);
  });

  // 同步 UID / P2P（返回 Future）
  final u = await abi.FooByUid(uidBytes, 10, 20);
  final p = await abi.FooByP2PName('my_p2p_group', 10, 20);

  // notify
  abi.FooNotify(10, 20);
  abi.FooSequencedNotify(10, 20);
  abi.FooNotifyByUid(uidBytes, 10, 20);
  abi.FooNotifyByP2PName('my_p2p_group', 10, 20);

  BridgeHost.instance.stop();
}

Future<void> _waitAsync<T>(String label, void Function(void Function(T?, String?)) starter) async {
  final completer = Completer<T?>();
  starter((result, error) {
    if (completer.isCompleted) return;
    if (error != null) {
      completer.completeError(StateError(error));
    } else {
      completer.complete(result);
    }
  });
  await completer.future.timeout(const Duration(seconds: 10));
}
```

**注意事项**

- **`ABI_TARGET_APP` / `ABI_TIMEOUT_MS`**：模块级 `String` / `int` 变量。
- **`Foo` 是 `Future`**：虽然内部是同步调用，但通过 `Isolate.run` 放到独立 isolate 执行，主 isolate 不阻塞。
- **`FooAsync` 是回调**：`void Function(T? result, String? error)`，需要在 `onResult` 中处理结果与错误。
- **`FooByUid` / `FooByP2PName` 是 `Future`**：内部走 `Framework.uidCallAsync` / `Framework.p2pnameCallAsync`。
- **`uid` 类型**：`Uint8List(32)`；`uid.length != 32` 抛 `RangeError`。
- **`BridgeHost.start()`**：必须先调用，加载 FFI 桥。
- **`BridgeHost.instance.stop()`**：进程退出前必须调用。

---

### 3.17 R

**Call 库文件**: `<Unit>_abi_call.R`

**支持的变体（精简版）**

Function（3 种）：
- `ApiName(...)`（同步 App）
- `ApiName_by_uid(uid, ...)`（同步 UID）
- `ApiName_by_p2p_name(p2p_name, ...)`（同步 P2P 组名）

Procedure（3 种）：
- `ApiName(...)`
- `ApiName_by_uid(uid, ...)`
- `ApiName_by_p2p_name(p2p_name, ...)`

**❌ 不支持异步调用（无 async / asyncSeq）**

**❌ 不支持 sequenced notify**

**开发平台**

| 项目 | 要求 |
|------|------|
| R | 4.x |
| 包 | `lingofuse`（2.0+） |
| 可选 | `bit64`（int64 / uint64 必需） |

**操作系统**: Windows / Linux / macOS。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `lingofuse` R 包 | `install.packages('lingofuse', repos='<your-repo>')` |
| `bit64` R 包（可选） | `install.packages('bit64')` |
| `LingoFuse64.dll` / `z_ipc_64.dll` | `Sys.setenv(LINGOFUSE_RUNTIME = '<path>')` 或放到脚本同目录 |

**接入代码**

```r
library(lingofuse)
source("<Unit>_abi_call.R")

# 加载运行时
runtime_dir <- find_runtime()
lf_load(runtime_dir)

# 设置 target
ABI_TARGET_APP <- "<Unit>_abi"
ABI_TIMEOUT    <- 5000

# 同步 App 调用
v <- Foo(10L, 20L)

# 同步 UID 调用
u <- Foo_by_uid(uid, 10L, 20L)

# 同步 P2P 调用
p <- Foo_by_p2p_name("my_p2p_group", 10L, 20L)

# notify
Foo(10L, 20L)
Foo_by_uid(uid, 10L, 20L)
Foo_by_p2p_name("my_p2p_group", 10L, 20L)

# 关闭
lf_cleanup(NULL)
```

**注意事项**

- **无异步**：R 侧完全没有 async / callback 机制；如需并发，请使用 R 的 `parallel` 包或 `future` 包，且每个 worker 独立启动 LingoFuse 运行时。
- **无 sequenced notify**：notify 只生成普通变体。
- **错误处理**：同步调用失败时 `stop()` 抛 `EABI_RemoteError`（实际上是 `stop()` 抛出一个普通错误）；用 `tryCatch` 捕获。
- **`bit64` 依赖**：`int64` / `uint64` 参数/返回值需要 `bit64`；缺失时 `*_test` 把相关变体标记为 SKIP。
- **`find_runtime()`**：来自 `lingofuse` 包，自动探测 `Binary/` / `runtime/` 等子目录；可用 `Sys.setenv(LINGOFUSE_RUNTIME=...)` 显式指定。
- **R 包 API surface**：`setup_R_tests.ps1` 会校验 13 个必需函数都存在；缺失时报错并退出 1。

---

## 4. 跨语言互操作注意事项

### 4.1 端点一致性

所有语言的 Call 库都默认连接：

```
ipc:<Unit>_abi
```

App 名默认 `<Unit>_abi`，P2P 组名默认 `<Unit>_service_test_p2p`。**两端必须由同一份源 unit 生成**，否则 API 名和类型表会不一致。

### 4.2 UID 传递

| 语言 | UID 类型 |
|------|----------|
| Pascal | `TP2P_UID___`（32 字节数组） |
| Python | `bytes` / hex string / `{bytes: Uint8Array(32)}` |
| C++ | `std::array<std::uint8_t, 32>` |
| C# | `P2PUid` |
| Rust | `lingofuse::uid::Uid` |
| Go | `sys.TP2P_UID`（`[32]byte` 封装） |
| Java | `byte[]` |
| Node.js / TS | `Uint8Array(32)` 或 hex string |
| Erlang | `<<_:256>>`（32 字节 binary） |
| Julia | `NTuple{32, UInt8}` |
| Zig | `lf.Uid` |
| Swift | `Uid` |
| Ruby | `String`（32 字节二进制） |
| Fortran | `integer(c_int8_t)(LF_UID_BYTE_COUNT)` |
| Dart | `Uint8List(32)` |
| R | `raw(32)` |

跨语言传递 UID 时，建议先序列化为 **64 字符 hex 字符串**，再在目标语言解析；这是唯一在所有语言上都无歧义的形式。

### 4.3 错误传播

| 语言 | 错误机制 |
|------|----------|
| Pascal | `EABI_RemoteError` 异常 |
| Python | `EABIRemoteError` 异常 |
| C++ | `EABI_RemoteError` 异常 |
| C# | `LingoFuseException` / `LingoFuseCallException` |
| Rust | `Result<T, Error>` |
| Go | `(T, error)` 双返回 |
| Java | `EABIRemoteError` 异常 |
| Node.js | Promise reject / `Error` |
| TypeScript | Promise reject / `Error` |
| Erlang | `{error, Reason}` 元组 |
| Julia | `EABI_RemoteError` 异常 |
| Zig | `Error!T` |
| Swift | `throws` / `LingoFuseError` |
| Ruby | `LingoFuse::CallError` 异常 |
| Fortran | `rc` 整数返回码 |
| Dart | `Future` reject / `StateError` |
| R | `stop()` 抛错误 |

**跨语言错误消息**：service 侧抛出的错误消息是 **UTF-8 字符串**；call 侧会以该语言的 `Error.message` 或 `EABI_RemoteError.what()` 呈现。

### 4.4 超时

| 语言 | 超时配置 |
|------|----------|
| Pascal | `ABI_Timeout: uint64`（unit 变量） |
| Python | `abi.ABI_TIMEOUT`（模块变量） |
| C++ | `<Unit>_abi::ABI_Timeout` |
| C# | `ABI.Timeout` |
| Rust | `ABI_TIMEOUT: AtomicU64` |
| Go | `ABI_Timeout: time.Duration` |
| Java | `<Unit>AbiCall.ABI_TIMEOUT` |
| Node.js | `ABI_Timeout`（getter/setter） |
| TypeScript | `ABI.Timeout` |
| Erlang | `?ABI_TIMEOUT_MS`（宏） |
| Julia | `ABI_Timeout[]`（Ref） |
| Zig | `ABI_TIMEOUT`（`pub var`） |
| Swift | `defaultTimeoutMs`（静态字段） |
| Ruby | `ABI_TIMEOUT_MS`（模块常量） |
| Fortran | 无全局超时（每个调用传 timeout 参数） |
| Dart | `ABI_TIMEOUT_MS` |
| R | `ABI_TIMEOUT`（每个调用传 timeout 参数） |

**Fortran 和 R 特别注意**：超时是每次调用独立的参数，不是全局配置；如果你需要全局超时，请在包装层处理。

### 4.5 线程模型

所有语言的 async 回调都在 **worker 线程**中执行。**不要在回调内调用阻塞的 LingoFuse 接口**（会导致死锁），也不要直接操作 UI。

若回调需要回到主线程：

- **Pascal / Delphi**：`TThread.Synchronize` / `TThread.Queue`
- **C#**：`SynchronizationContext.Post` 或 `TaskScheduler.FromCurrentSynchronizationContext()`
- **Java**：`Platform.runLater`（JavaFX）/ `SwingUtilities.invokeLater`（Swing）
- **Swift**：`await MainActor.run { ... }` 或 `DispatchQueue.main.async { ... }`
- **Python**：`loop.call_soon_threadsafe`（asyncio）
- **JS / TS / Node.js**：本身单线程；回调中若用 `await`，注意 Promise 链的上下文

---

## 5. 常见问题

### Q1: 为什么 Fortran 和 R 不支持异步调用？

Fortran 和 R 的生态里没有 **fiber / coroutine / async runtime** 这类与 LingoFuse worker 模型对齐的机制；强行引入回调会破坏这两门语言的数据流风格（Fortran 的纯函数 + 显式 `rc`，R 的 vectorized 求值）。因此生成器对它们只输出 **3 种同步调用** 与 **3 种同步 notify**（app / uid / p2p）。

若你需要并发，请：

- **Fortran**：用 OpenMP 或 `!$omp parallel` + 每线程独立调用同步接口；或用一个线程池。
- **R**：用 `parallel` / `future` 包；每个 worker 独立启动 LingoFuse 运行时（`lf_load`）。

### Q2: 为什么 Erlang 没有 sequenced async？

Erlang 的生成器只生成了 `_async`、`_uid_async`、`_p2p_async` 三种异步函数，**没有 `_async_sequenced`**。Erlang 的异步模型是"spawn 一个 Collector 进程接收 `{lf_async_result, Ref, ...}` 消息"，本身没有"顺序"概念。若你需要顺序，请：

- 用 `gen_server` 串行化调用；
- 或在 async 回调中显式把结果投递到同一个 `gen_server`。

### Q3: 异步 notify 和同步 notify 有区别吗？

**没有**。notify 本身就是"发出去不等回复"，无论 `Foo` 还是 `Foo_SequencedNotify`，caller 都立即返回。区别仅在 **service 侧处理顺序**：

- `Foo`：service 可能在多个 worker 线程并发处理；
- `Foo_SequencedNotify`：LingoFuse 保证同一个连接的多个 notify 按调用顺序投递。

### Q4: UID 变体在哪些语言里可用？

**所有 17 种语言**都支持。但 **Fortran / R 只支持 UID 同步**（无 UID async）；**Erlang 有 `_uid` 与 `_uid_async`，但无 `_uid_async_sequenced`**。详见 [§2.1](#21-变体数量)。

### Q5: 同一个进程里调用多个 service 需要不同的 TargetApp 吗？

需要。`ABI_TargetApp`（各语言命名不同）是**全局配置**；如果同时调用两个 service，你需要在每次调用前**改 `TargetApp`**，或者：

- 使用 UID / P2P 组名变体（它们绕过 `TargetApp`）；
- 用不同的 call 库实例（**不推荐**，会重复加载运行时）。

### Q6: 跨平台部署时有哪些注意点？

- **UID 字节序**：UID 是**不透明的 32 字节**，没有字节序问题；建议用 hex 字符串传输。
- **字符串编码**：所有语言的 call 库都按 **UTF-8** 编码字符串；跨语言调用时无歧义。
- **数字类型**：`int64` / `uint64` 在 JS / TS / Erlang / Ruby 里可能精度丢失（JS / TS 用 `bigint`，Ruby 用 `Integer`，Erlang 用 `integer`）；确保生成器输出使用正确的类型。
- **NaN / Infinity**：float 的 `NaN` / `Infinity` 在二进制层面可传输；JSON 路径不支持，但 ABI 路径**支持**。
- **空字符串 vs null**：所有语言的 call 库都按"`NUL` 终止的 UTF-8 字节"编码字符串；**空字符串**编码为单个 `NUL` 字节；**`null` 字符串**在 ABI 路径里**没有语义**（必须用空字符串表示）。

### Q7: 回调里调用 LingoFuse 会死锁吗？

会。**回调在 worker 线程执行；worker 线程池大小固定**。若回调内同步调用 `LF_Call` / `LF_Notify`，会占满 worker 线程并等待另一个 worker 线程，导致死锁。

**正确做法**：

- 把回调内的 LingoFuse 调用**投递到独立线程**（`std::thread` / `TThread.CreateAnonymousThread` / `Task.Run` / `Thread` / `spawn` 等）；
- 或改用 async 接口，让回调本身不阻塞。

### Q8: 生成器输出的 call 库可以手动修改吗？

可以，但**不推荐**。生成器会按**源 unit 的当前状态**重新生成所有文件；如果你改了 `<Unit>_abi_call.<ext>`，重新生成时会被覆盖。如需定制：

- 用**包装器**：在生成的库之上再写一层；
- 或把定制逻辑放在 `internal_call_<Api>`（service 侧）而不是 call 侧；
- 或给生成器打补丁（参见 `code_decl_to_abi_OPERATIONS.md`）。

### Q9: 为什么 Python 有 `_Aio` 而其他语言没有？

Python 的 `async/await` 是**原生语言特性**，可以生成 `async def` 函数让用户直接 `await`；其他语言（Go 的 goroutine、Rust 的 `Future` trait、C# 的 `Task`、Swift 的 `async` 等）的 async 模型与 LingoFuse 的 callback 模型更接近，用 callback / Future / Promise / Task 包装即可。Python 的 `_Async`（返回 `CallFuture`）与 `_Aio`（`async def`）互为补充：前者适合非 asyncio 场景，后者适合 asyncio 应用。

### Q10: C# / Java 的 call 库能否与 WPF / WinForms / Android 一起用？

**可以**，但要注意**线程**：

- **WPF / WinForms**：async 回调在 worker 线程执行；UI 更新需 `Dispatcher.Invoke` / `Control.Invoke`。推荐用 `await` 让编译器自动切回 UI 线程（WPF / WinForms 的 `SynchronizationContext` 会处理）。
- **ASP.NET Core**：无 `SynchronizationContext`，`await` 后仍在 worker 线程；避免依赖线程本地状态。
- **Android**：async 回调在 worker 线程；UI 更新需 `runOnUiThread` / `Handler(Looper.getMainLooper())`。

---

**文档版本**: 1.0
**文档定位**: `code_decl_to_abi` 生成的 17 种目标语言的 **Call 库**接入指南 —— 覆盖变体列表、异步能力、开发平台、操作系统、依赖、安装、最小接入代码、注意事项。
**配套文档**: `code_decl_to_abi_USER_GUIDE.md`（端到端用户指南）、`code_decl_to_abi_TESTING_GUIDE.md`（测试方法）、`code_decl_to_abi_OPERATIONS.md`（内部实现与扩展）。
**生成代码语言**: 英文。本文档语言: 中文。
