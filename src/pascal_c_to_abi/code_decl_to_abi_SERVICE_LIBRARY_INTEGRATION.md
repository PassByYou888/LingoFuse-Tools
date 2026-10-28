# code_decl_to_abi — 各语言 Service 库接入指南

> **文档定位**: 详细说明 `code_decl_to_abi` 生成的 **Service 库**（服务侧）在 17 种目标语言中的接入方式，涵盖 library 的职责、生命周期、回调线程模型、每个语言的 API 表面、开发平台要求、操作系统支持、最小接入代码、以及与 Call 库的协作注意事项。
>
> **前置阅读**: `code_decl_to_abi_USER_GUIDE.md`（整体工具与工作流）、`code_decl_to_abi_TESTING_GUIDE.md`（测试方法）、`code_decl_to_abi_CALL_LIBRARY_INTEGRATION.md`（Call 库接入）。
>
> **文档语言**: 中文。
>
> **生成代码语言**: 英文。

---

## 目录

1. [Service 库的职责与生命周期](#1-service-库的职责与生命周期)
2. [跨语言统一概念](#2-跨语言统一概念)
3. [总览能力矩阵](#3-总览能力矩阵)
4. [各语言详细接入](#4-各语言详细接入)
   - [4.1 Pascal](#41-pascal)
   - [4.2 Python](#42-python)
   - [4.3 C++](#43-c)
   - [4.4 C#](#44-c)
   - [4.5 Rust](#45-rust)
   - [4.6 Go](#46-go)
   - [4.7 Java](#47-java)
   - [4.8 Node.js](#48-nodejs)
   - [4.9 TypeScript](#49-typescript)
   - [4.10 Erlang](#410-erlang)
   - [4.11 Julia](#411-julia)
   - [4.12 Zig](#412-zig)
   - [4.13 Swift](#413-swift)
   - [4.14 Ruby](#414-ruby)
   - [4.15 Fortran](#415-fortran)
   - [4.16 Dart](#416-dart)
   - [4.17 R](#417-r)
5. [Service 与 Call 的协作注意事项](#5-service-与-call-的协作注意事项)
6. [常见问题](#6-常见问题)

---

## 1. Service 库的职责与生命周期

### 1.1 Service 库的职责

Service 库负责**被动响应**调用方：

1. **注册**声明的 API 到 LingoFuse App；
2. **解码**来自 call 侧的二进制请求；
3. **调用**用户实现的 `internal_call_<Api>` 桩函数；
4. **编码**返回值（或错误）为二进制响应；
5. 提供 **notify 回调**（无返回值）；
6. 支持**主动反向调用** client（可选场景，如 `LF_TEST_ASK_SERVICE_CALL_ME`）。

### 1.2 生命周期（跨语言一致）

```
┌──────────────────────────────────────────────────────────────┐
│  1. LF_ResetPrepare()                                        │
│  2. LF_PrepareService(listenAddr, physicsAddr)               │
│  3. LF_CreateApp(DEFAULT_APP_NAME, DEFAULT_APP_DESC)         │
│  4. Register_All_ABI_APIs(App)      ← 用户 API 注册          │
│  5. LF_RegisterCall / Notify (辅助 API，可选)                │
│  6. LF_PrepareClient(endpoint, App)                          │
│  7. LF_PrepareDone()                                         │
│  8. (事件循环)                                                │
│  9. LF_ExitMainThread()                                      │
│ 10. LF_FreeApp(App)                                          │
│ 11. LF_Shutdown()                                            │
└──────────────────────────────────────────────────────────────┘
```

**第 4 步是核心**：`Register_All_ABI_APIs` 由生成器提供，负责把源 unit 中所有 routine 注册为 LingoFuse API。它内部会遍历所有 API 调用 `LF_RegisterCall`（有返回值）或 `LF_RegisterNotify`（无返回值）。

### 1.3 回调线程模型

**所有语言的 service 回调都在 LingoFuse worker 线程中执行**（不是主线程）。这意味着：

- `internal_call_<Api>` 桩体在 worker 线程执行；
- `Callback_<Api>` 在 worker 线程执行；
- 回调内不能阻塞，不能调用阻塞的 LingoFuse 接口；
- 若要操作 UI 或访问非线程安全的资源，需要切回主线程。

### 1.4 与 Call 库的区别

| 维度 | Service 库 | Call 库 |
|------|-----------|---------|
| 角色 | 被动响应 | 主动发起 |
| 触发方式 | 由 LingoFuse worker 触发 | 由用户代码触发 |
| 主要 API | `Register_All_ABI_APIs` / `internal_call_<Api>` | `Foo` / `Foo_Async` / ... |
| 返回值处理 | 由回调内部写入 Out 句柄 | 由 caller 读取返回值 |
| 线程 | 回调在 worker 线程 | 同步调用在用户线程；异步回调在 worker 线程 |

---

## 2. 跨语言统一概念

### 2.1 三种核心 API 变体

无论哪种语言，service 库都会生成以下三类入口：

| 类别 | 生成内容 | 说明 |
|------|----------|------|
| **内部调用桩** | `internal_call_<Api>(uid, p2p_name, [args])` | **用户填充实现**；LingoFuse 收到请求后调用此桩 |
| **LingoFuse 回调** | `Callback_<Api>(in, out)`（Call）/ `Callback_<Api>(in)`（Notify） | **不修改**；负责解码、调用桩、编码响应 |
| **注册函数** | `Register_All_ABI_APIs(app)` / `Register_All_P2P_ABI_APIs()` | **不修改**；批量注册所有 API |

部分语言额外提供 `Create_And_Register_ABI_App()` 一次性完成 CreateApp + RegisterAll 的便捷函数。

### 2.2 App 命名约定

所有语言的 service 库在生成时都注入两个常量：

| 常量 | 值 |
|------|-----|
| `DEFAULT_APP_NAME` | `<UnitName>_abi` |
| `DEFAULT_APP_DESC` | `ABI service for <UnitName>` |

这些常量用于 `LF_CreateApp`。跨进程调用时，**call 侧的 `ABI_TargetApp` 必须与之匹配**。

### 2.3 线协议（跨语言一致）

Service 库按以下顺序处理每个请求：

1. 从 `in` 句柄读取 `uid`（32 字节）与 `p2p_name`（UTF-8 NUL 结尾）；
2. 按参数表顺序解码每个参数；
3. 调用 `internal_call_<Api>(uid, p2p_name, [args])`；
4. 写入响应：`[status:uint8_t][payload]`：
   - `0x00` + 序列化结果（function）；
   - `0x00`（procedure）；
   - `0xFF` + UTF-8 错误消息（异常）。

### 2.4 P2P 组注册

`Register_All_P2P_ABI_APIs()` 把 API 注册到 P2P 组，使得 call 侧可以通过 P2P 组名（而不是 App 名或 UID）定位 service。调用此函数前需要先 `LF_Set_Opt_P2P_Name("<UnitName>_service_test_p2p")`（各语言方法名略有不同）。

---

## 3. 总览能力矩阵

### 3.1 Service 库能力矩阵

| 语言 | Service 生成函数 | `internal_call` 桩 | `Callback` | `Register_All_ABI_APIs` | `Register_All_P2P_ABI_APIs` | `Create_And_Register` |
|------|:----------------:|:------------------:|:----------:|:-----------------------:|:---------------------------:|:---------------------:|
| Pascal | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Python | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| C++ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| C# | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Rust | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Go | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Java | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Node.js | ✅ | ✅ | ✅ | ✅ | ✅ | ❌（需手工建 App） |
| TypeScript | ✅ | ✅ | ✅ | ✅ | ✅ | ❌（需手工建 App） |
| Erlang | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Julia | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Zig | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Swift | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Ruby | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Fortran | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dart | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| R | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

> **Node.js / TypeScript** 的 `registerAll` 接收 app 参数，但未提供 `CreateAndRegisterABIApp()` 辅助函数，需要用户手工：

```javascript
const app = new lf.AppHandle(APP_NAME, APP_DESC);
service.registerAll(app.raw);
```

### 3.2 平台与操作系统支持

| 语言 | 开发平台（SDK / 运行时） | Windows | Linux | macOS | 备注 |
|------|-------------------------|:-------:|:-----:|:-----:|------|
| Pascal | FPC 3.2+ / Delphi 10.4+ | ✅ | ✅ | ✅ | 需 `lingofuse_import.pas` + `Z.Core` |
| Python | CPython 3.7+ | ✅ | ✅ | ✅ | 需 `py-lingofuse` |
| C++ | C++17 编译器 | ✅ | ✅ | ✅ | 需 `LingoFuse.hpp` + `LingoFuse.c` |
| C# | .NET 6+ | ✅ | ✅ | ✅ | 需 `lingofuse` 命名空间 |
| Rust | Rust 2021 edition | ✅ | ✅ | ✅ | 需 `lingofuse` crate |
| Go | Go 1.21+ | ✅ | ✅ | ✅ | 需 `lingofuse/go` module |
| Java | JDK 22+ | ✅ | ✅ | ✅ | 需 `lingofuse.jar` |
| Node.js | Node.js 18+ | ✅ | ✅ | ✅ | 需 `lingofuse-js` + `koffi` |
| TypeScript | TypeScript 5.6+ / Node.js 18+ | ✅ | ✅ | ✅ | 需 `lingofuse-ts` |
| Erlang | OTP 27+ | ✅ | ✅ | ✅ | 需 `lingofuse.beam` |
| Julia | Julia 1.9+（**必须 `--threads=2`**） | ✅ | ✅ | ✅ | 异步依赖多线程 |
| Zig | Zig 0.17+ | ✅ | ✅ | ✅ | 需 `lingofuse` Zig 包 |
| Swift | Swift 5.9+ | ⚠️（5.9+ 有工具链） | ⚠️（社区验证） | ✅（主要支持） | 生产环境建议 macOS / Linux |
| Ruby | Ruby 3.0+ | ✅ | ✅ | ✅ | 需 `lingofuse` gem |
| Fortran | gfortran 9+ + gcc 9+ + g++ 9+ | ✅ | ✅ | ✅ | 需 `lf_fortran_mod` |
| Dart | Dart 3.0+ | ✅ | ✅ | ✅ | 需 `lingofuse` Dart 包 + `lf_dart_bridge.dll` |
| R | R 4.x | ✅ | ✅ | ✅ | 需 `lingofuse` R 包 |

### 3.3 共用运行时依赖

| 文件 | 作用 |
|------|------|
| `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` | LingoFuse 核心运行时 |
| `z_ipc_*.dll` / `libz_ipc_*.so` | IPC 传输插件 |

各语言绑定包（`.whl` / `.gem` / `.crate` / `.jar` 等）都是上述运行时的包装。

---

## 4. 各语言详细接入

### 4.1 Pascal

**Service 库文件**: `<Unit>_abi_service_unit.pas`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DEFAULT_APP_NAME: string`, `DEFAULT_APP_DESC: string` |
| 全局 | `DEBUG_LOG: boolean` |
| 用户桩 | `internal_call_<Api>(UID___: TP2P_UID___; p2pName___: string; [args]): T`（function）<br>`internal_call_<Api>(...): void`（procedure） |
| LingoFuse 回调 | `Callback_<Api>(_Trigger, _In_, _Out_) cdecl`（Call）<br>`Callback_<Api>(_Trigger, _In_) cdecl`（Notify） |
| 注册 | `Register_All_ABI_APIs(App: TAppHnd___)` |
| 注册 | `Register_All_P2P_ABI_APIs()` |
| 便捷 | `Create_And_Register_ABI_App: TAppHnd___` |

**开发平台**

| 项目 | 要求 |
|------|------|
| 编译器 | Free Pascal 3.2+ / Delphi 10.4+ |
| 语言模式 | Delphi 模式（`{$mode delphi}`） |
| 源码编码 | UTF-8（`{$CODEPAGE UTF8}`） |

**操作系统**: Windows / Linux / macOS。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `lingofuse_import.pas` | `-Fu<dir-with-lingofuse_import.pas>` |
| `Z.Core` | `-Fu<dir-with-Z.Core.pas>` |
| `lingofuse_helper.pas`（可选） | `-Fu<dir-with-lingofuse_helper.pas>` |

**接入代码**

```pascal
uses
  SysUtils,
  lingofuse_import,
  <Unit>_abi_service_unit;

// 1. 填充 internal_call 桩体
function <Unit>_abi_service_unit.internal_call_Foo(
  UID___: TP2P_UID___; p2pName___: string;
  a: Integer; b: Integer): Integer;
begin
  // 调用真实业务函数
  Result := a + b;
end;

// 2. 启动 service
var
  App: TAppHnd___;
begin
  LF_ResetPrepare();
  LF_Set_Opt_Quiet(True);
  LF_Set_Opt_ConsoleOutput(True);

  LF_PrepareServiceEx('ipc:<Unit>_abi', 'ipc:<Unit>_abi');

  App := LF_CreateAppEx(DEFAULT_APP_NAME, DEFAULT_APP_DESC);
  if App = nil then
  begin
    WriteLn('CreateApp failed');
    Halt(1);
  end;

  // 注册所有 API（含用户 API + 桩体）
  Register_All_ABI_APIs(App);

  // 注册测试辅助 API（可选，用于 call 侧 UID 探测）
  LF_RegisterCallEx(App, 'LF_TEST_WHOAMI',
    'service-side whoami helper', nil, @Test_CB_WHOAMI);
  LF_RegisterNotifyEx(App, 'LF_TEST_ASK_SERVICE_CALL_ME',
    'ask service to call back client', nil, @Test_CB_ASK_SERVICE_CALL_ME);

  // 注册 P2P 组
  LF_Set_Opt_P2P_Name('<Unit>_service_test_p2p');
  Register_All_P2P_ABI_APIs();

  // 连接到 IPC 端点
  if LF_PrepareClientEx('ipc:<Unit>_abi', App) = -1 then
  begin
    LF_FreeApp(App);
    Halt(1);
  end;

  if LF_PrepareDone() <> 1 then
  begin
    LF_ExitMainThread();
    LF_FreeApp(App);
    LF_Shutdown();
    Halt(1);
  end;

  WriteLn('[OK] service ready');
  ReadLn;  // 按 Enter 停止

  // 3. 关闭
  LF_ExitMainThread();
  LF_FreeApp(App);
  LF_Shutdown();
end.
```

**注意事项**

- **`LF_RegisterCallEx` 与 `LF_RegisterNotifyEx`**：前者用于有返回值的 function，后者用于 procedure。
- **`Callback_<Api>` 签名**：Call 类型是 `(_Trigger, _In_, _Out_)`，Notify 类型是 `(_Trigger, _In_)`；使用 `cdecl` 调用约定。
- **UID 类型**：`TP2P_UID___` 是 `array[0..31] of Byte`。
- **`DEBUG_LOG`**：设为 `True` 时回调会打印诊断信息。

---

### 4.2 Python

**Service 库文件**: `<Unit>_abi_service.py`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DEFAULT_APP_NAME`, `DEFAULT_APP_DESC`, `API_COUNT`, `DEBUG_LOG` |
| 用户桩 | `internal_call_<api>(_lf_uid, _lf_p2p_name, [args])` |
| LingoFuse 回调 | `Callback_<api>(_Trigger, _In, _Out)`（Call，`@LFCallFunc`）<br>`Callback_<api>(_Trigger, _In)`（Notify，`@LFNotifyFunc`） |
| 注册 | `Register_All_ABI_APIs(app)` |
| 注册 | `Register_All_P2P_ABI_APIs()` |
| 便捷 | `Create_And_Register_ABI_App()` |
| 序列化 | `_read_int32` / `_write_int32` / `_read_string` / ... 全套 |

**开发平台**

| 项目 | 要求 |
|------|------|
| Python | CPython 3.7+ |
| 可选依赖 | 无 |

**操作系统**: Windows / Linux / macOS。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `lingofuse` Python 包 | `pip install py-lingofuse` 或 `PYTHONPATH=<v3>/src` |

**接入代码**

```python
from lingofuse._lf_native import (
    LF_ResetPrepare, LF_PrepareService, LF_PrepareClient,
    LF_PrepareDone, LF_CreateApp, LF_RegisterCall, LF_RegisterNotify,
    LF_ExitMainThread, LF_FreeApp, LF_Shutdown,
)
from lingofuse.lf_io import cstr
import <Unit>_abi_service as svc

# 1. 填充 internal_call 桩体
def _patched_internal_call_Foo(_lf_uid, _lf_p2p_name, a, b):
    return a + b

svc.internal_call_Foo = _patched_internal_call_Foo

# 2. 启动 service
LF_ResetPrepare()
LF_PrepareService(cstr("ipc:<Unit>_abi"), cstr("ipc:<Unit>_abi"))

app = svc.Create_And_Register_ABI_App()
if app is None:
    raise SystemExit(1)

# 可选：注册测试辅助 API
LF_RegisterCall(app, cstr("LF_TEST_WHOAMI"),
                cstr("whoami helper"), None, my_whoami_cb)
LF_RegisterNotify(app, cstr("LF_TEST_ASK_SERVICE_CALL_ME"),
                  cstr("ask service to call back client"), None, my_ask_cb)

# 注册 P2P
from lingofuse.lf_io import cstr as _c
from lingofuse._lf_native import LF_Set_Opt_P2P_Name
LF_Set_Opt_P2P_Name(_c("<Unit>_service_test_p2p"))
svc.Register_All_P2P_ABI_APIs()

if LF_PrepareClient(cstr("ipc:<Unit>_abi"), app) == -1:
    raise SystemExit(1)
if LF_PrepareDone() != 1:
    raise SystemExit(1)

print("[OK] service ready")
input()  # 按 Enter 停止

# 3. 关闭
LF_ExitMainThread()
LF_FreeApp(app)
LF_Shutdown()
```

**注意事项**

- **`internal_call_<api>` 桩的替换方式**：Python 不支持函数前向声明，所以直接**重新赋值** `svc.internal_call_Foo = _patched_internal_call_Foo`（或者更优雅地继承/子类化 `svc` 模块）。
- **`@LFCallFunc` / `@LFNotifyFunc`**：装饰器把普通 Python 函数转换成 ctypes 兼容的回调；`Create_And_Register_ABI_App()` 内部已经处理好了所有 `Callback_<api>` 的注册。
- **`internal_call` 签名**：第一个参数是 `_lf_uid`（`bytes` 32 字节），第二个是 `_lf_p2p_name`（`str`）；后续是用户参数。
- **返回值**：直接 `return` 即可，框架自动编码。
- **`DEBUG_LOG`**：设为 `True` 时回调会打印诊断信息。

---

### 4.3 C++

**Service 库文件**: `<Unit>_abi_service.hpp` + `<Unit>_abi_service.cpp`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DEFAULT_APP_NAME`, `DEFAULT_APP_DESC` |
| 用户桩 | `T internal_call_<Api>(const std::array<uint8_t,32>& _lf_uid, const std::string& _lf_p2p_name, [args])` |
| LingoFuse 回调 | `void LF_CDECL Callback_<Api>(void* _Trigger, void* _In, void* _Out)` |
| 注册 | `int Register_All_ABI_APIs(TAppHnd app)`（返回失败数） |
| 注册 | `int Register_All_P2P_ABI_APIs()` |
| 便捷 | `TAppHnd Create_And_Register_ABI_App()` |
| 序列化 | `Safe_Write_Error` / `Safe_Write_Scalar<T>` / `Safe_Write_String` / `Safe_Write_Void` |

**开发平台**

| 项目 | 要求 |
|------|------|
| C++ 标准 | C++17 |
| 编译器 | MSVC 2019+ / g++ 9+ / clang++ 10+ |
| 构建系统 | 推荐 CMake 3.15+（`CMakeLists.txt` 由生成器一并产出） |

**操作系统**: Windows / Linux / macOS。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `LingoFuse.hpp` / `lf_io.hpp` | `-I<dir-with-headers>` |
| `LingoFuse.c` | 编译进项目（CMake 里作为 `lingofuse_c_wrapper` 静态库） |

**接入代码**

```cpp
#include "<Unit>_abi_service.hpp"
#include "LingoFuse.hpp"
#include "lf_io.hpp"

// 1. 填充 internal_call 桩体
namespace <Unit>_abi {
int64_t internal_call_Foo(
    const std::array<std::uint8_t, 32>& _lf_uid,
    const std::string& _lf_p2p_name,
    int64_t a, int64_t b) {
  (void)_lf_uid;
  (void)_lf_p2p_name;
  return a + b;
}
}  // namespace <Unit>_abi

// 2. 启动 service
int main() {
  if (LF_LoadLibrary() != 1) {
    std::fprintf(stderr, "[FATAL] LF_LoadLibrary failed\n");
    return 1;
  }

  LF_ResetPrepare();
  LF_Set_Opt_Quiet(1);
  LF_Set_Opt_ConsoleOutput(1);
  LF_PrepareService("ipc:<Unit>_abi", "ipc:<Unit>_abi");

  TAppHnd app = <Unit>_abi::Create_And_Register_ABI_App();
  if (app == nullptr) {
    std::fprintf(stderr, "[FATAL] Create_And_Register_ABI_App failed\n");
    LF_Shutdown();
    LF_FreeLibrary();
    return 1;
  }

  // 可选：注册测试辅助 API
  LF_RegisterCall(app, "LF_TEST_WHOAMI",
                  "whoami helper", nullptr, &MyWhoAmICb);
  LF_RegisterNotify(app, "LF_TEST_ASK_SERVICE_CALL_ME",
                    "ask service to call back client", nullptr, &MyAskCb);

  // P2P
  LF_Set_Opt_P2P_Name("<Unit>_service_test_p2p");
  <Unit>_abi::Register_All_P2P_ABI_APIs();

  if (LF_PrepareClient("ipc:<Unit>_abi", app) == -1) {
    std::fprintf(stderr, "[FATAL] PrepareClient failed\n");
    LF_FreeApp(app);
    LF_Shutdown();
    LF_FreeLibrary();
    return 1;
  }

  if (LF_PrepareDone() != 1) {
    LF_ExitMainThread();
    LF_FreeApp(app);
    LF_Shutdown();
    LF_FreeLibrary();
    return 1;
  }

  std::printf("[OK] service ready\n");
  std::getchar();

  // 3. 关闭
  LF_ExitMainThread();
  LF_FreeApp(app);
  LF_Shutdown();
  LF_FreeLibrary();
  return 0;
}
```

**CMake 集成**

```cmake
cmake_minimum_required(VERSION 3.15)
project(my_service LANGUAGES CXX C)
set(CMAKE_CXX_STANDARD 17)

find_package(Threads REQUIRED)

add_library(lingofuse_c_wrapper STATIC ${LINGOFUSE_CPP_DIR}/LingoFuse.c)
target_include_directories(lingofuse_c_wrapper PUBLIC ${LINGOFUSE_CPP_DIR})

add_library(<Unit>_abi_service STATIC <Unit>_abi_service.cpp)
target_include_directories(<Unit>_abi_service PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(<Unit>_abi_service PUBLIC lingofuse_c_wrapper Threads::Threads)

add_executable(my_service main.cpp)
target_link_libraries(my_service PRIVATE <Unit>_abi_service)
```

**注意事项**

- **`LF_LoadLibrary()`**：必须先调用；返回 1 表示成功。
- **`Safe_Write_*` 系列**：由生成器提供，用于在回调中安全地写响应；不要用裸 `LF_WriteBuffer`。
- **`LF_RegisterCall` / `LF_RegisterNotify`**：Call 用于 function，Notify 用于 procedure。
- **回调签名**：`void LF_CDECL Callback_<Api>(void*, void*, void*)`（Call）或 `(void*, void*)`（Notify）。
- **MSVC**：必须加 `/utf-8`，否则 API 描述字符串会以系统 codepage 编码。

---

### 4.4 C#

**Service 库文件**: `<Unit>_abi_service.cs`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `AppInfo.Name`, `AppInfo.Desc` |
| 用户桩 | `InternalCalls.InternalCall_<Api>(P2PUid lfUid, string lfP2PName, [args])` |
| LingoFuse 回调 | `Callbacks.Callback_<Api>(DataHandle inHandle, DataHandle outHandle)`（Call）<br>`Callbacks.Callback_<Api>(DataHandle inHandle)`（Notify） |
| 注册 | `Service.RegisterAllABIAPIs(AppHandle app)` |
| 注册 | `Service.RegisterAllP2PABIAPIs()` |
| 便捷 | `Service.CreateAndRegisterABIApp()` |

**开发平台**

| 项目 | 要求 |
|------|------|
| .NET | .NET 6+ |
| 语言 | C# 10+ |
| 项目类型 | 任意（Console / WPF / WinForms / ASP.NET Core / MAUI / Worker Service） |

**操作系统**: Windows / Linux / macOS。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `lingofuse` 命名空间 | 拷贝 `<Unit>_abi_service.cs` 到项目 |

**接入代码**

```csharp
using System;
using lingofuse;
using <Unit>_abi_service;

class Program
{
    // 1. 填充 InternalCall 桩体
    //    在 Service 类中定义：InternalCalls.InternalCall_Foo
    //    在项目里新建一个 partial class：
    //    public static partial class InternalCalls
    //    {
    //        public static int InternalCall_Foo(P2PUid lfUid, string lfP2PName, int a, int b)
    //        {
    //            return a + b;
    //        }
    //    }

    static void Main()
    {
        Framework.ResetPrepare();
        Options.SetQuiet(true);
        Options.SetConsoleOutput(true);

        Framework.PrepareService("ipc:<Unit>_abi", "ipc:<Unit>_abi");

        AppHandle app = Service.CreateAndRegisterABIApp();
        if (app == null) { Environment.Exit(1); }

        // 可选：注册测试辅助 API
        app.RegisterCall("LF_TEST_WHOAMI", "whoami helper", MyWhoAmICb);
        app.RegisterNotify("LF_TEST_ASK_SERVICE_CALL_ME", "ask service", MyAskCb);

        // P2P
        Options.SetP2PName("<Unit>_service_test_p2p");
        Service.RegisterAllP2PABIAPIs();
        Framework.RegisterP2PCall("LF_TEST_WHOAMI", "whoami helper", MyWhoAmICb);

        if (Framework.PrepareClient("ipc:<Unit>_abi", app) == -1)
        {
            app.Dispose();
            Environment.Exit(1);
        }
        if (Framework.PrepareDone() != 1)
        {
            Framework.ExitMainThread();
            app.Dispose();
            Environment.Exit(1);
        }

        Console.WriteLine("[OK] service ready");
        Console.ReadLine();

        // 3. 关闭
        Framework.ExitMainThread();
        app.Dispose();
        Framework.Shutdown();
    }

    static void MyWhoAmICb(DataHandle inHandle, DataHandle outHandle) { /* ... */ }
    static void MyAskCb(DataHandle inHandle) { /* ... */ }
}
```

**注意事项**

- **`partial class InternalCalls`**：生成器不会自动帮你创建 partial 类；需要在同一项目中另建一个 `.cs` 文件声明 `public static partial class InternalCalls`，把 `InternalCall_Foo` 的真实实现填进去。
- **`Callbacks` 的 `static readonly` 字段**：生成器确保每个回调 delegate 都被静态持有，避免 GC 回收；**不要删除**这些字段。
- **`P2PUid` 类型**：32 字节 UID；`IsEmpty` / `ToByteArray` / `FromBytes`。
- **`DataHandle`**：请求/响应句柄；`ReadInt32` / `WriteInt32` / `ReadString` / `WriteString` 等。

---

### 4.5 Rust

**Service 库文件**: `<Unit>_abi_service.rs`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DEFAULT_APP_NAME: &str`, `DEFAULT_APP_DESC: &str`, `STATUS_OK`, `STATUS_ERROR` |
| 用户桩 | `internal_call_<api>(uid: Uid, p2p_name: &str, [args]) -> T` |
| LingoFuse 回调 | `callback_<api>(input: &mut DataHandle, output: &mut DataHandle)`（Call）<br>`callback_<api>(input: &mut DataHandle)`（Notify） |
| 注册 | `register_all_abi_apis(app: &AppHandle) -> Result<(), Error>` |
| 注册 | `register_all_p2p_abi_apis() -> Result<(), Error>` |
| 便捷 | `create_and_register_abi_app() -> Result<AppHandle, Error>` |

**开发平台**

| 项目 | 要求 |
|------|------|
| Rust | 2021 edition |
| 工具链 | rustc 1.70+ / cargo |

**操作系统**: Windows / Linux / macOS。

**依赖**

```toml
[dependencies]
lingofuse = { path = "<LingoFuse>/rust" }
```

**接入代码**

```rust
use <Unit>_abi::service;

// 1. 填充 internal_call 桩体
//    在 src/service.rs 里直接改 internal_call_Foo 的函数体：
//    pub fn internal_call_foo(uid: Uid, p2p_name: &str, a: i64, b: i64) -> i64 {
//        let _ = (uid, p2p_name);
//        a + b
//    }

fn main() -> Result<(), Box<dyn std::error::Error>> {
    lingofuse::framework::init()?;

    lingofuse::options::set_quiet(true)?;
    lingofuse::options::set_console_output(true)?;

    lingofuse::framework::reset_prepare();
    lingofuse::framework::prepare_service("ipc:<Unit>_abi", "ipc:<Unit>_abi")?;

    let app = service::create_and_register_abi_app()?;

    // 可选：注册测试辅助 API
    app.register_call("LF_TEST_WHOAMI", "whoami helper", cb_whoami)?;
    app.register_notify("LF_TEST_ASK_SERVICE_CALL_ME", "ask", cb_ask)?;

    // P2P
    lingofuse::options::set_p2p_name("<Unit>_service_test_p2p")?;
    service::register_all_p2p_abi_apis()?;
    lingofuse::p2p::register_p2p_call("LF_TEST_WHOAMI", "whoami", cb_whoami)?;

    lingofuse::framework::prepare_client("ipc:<Unit>_abi", Some(&app))?;
    if !lingofuse::framework::prepare_done()? {
        return Err("prepare_done failed".into());
    }

    println!("[OK] service ready");
    let _ = std::io::stdin().read(&mut [0u8]);

    // 3. 关闭
    drop(app);
    lingofuse::framework::exit_main_thread();
    lingofuse::framework::shutdown();
    Ok(())
}

fn cb_whoami(_in: &mut lingofuse::data_handle::DataHandle,
             _out: &mut lingofuse::data_handle::DataHandle) {
    // ...
}

fn cb_ask(_in: &mut lingofuse::data_handle::DataHandle) {
    // ...
}
```

**注意事项**

- **`internal_call_<api>` 桩**：生成器直接把它写在 `src/service.rs` 里，**你直接编辑该文件**。
- **`callback_<api>` 的 panic 安全**：生成器在回调内部用 `std::panic::catch_unwind` 包装了 `internal_call`；你的桩即使 panic 也会被安全处理。
- **`register_all_abi_apis`** 返回 `Result<(), Error>`；失败时立即返回错误。
- **`Uid` / `DataHandle`**：来自 `lingofuse` crate；`Uid::from_bytes([u8; 32])`。
- **`lib.rs`**：需要声明 `pub mod service;`（`setup_rust_tests.ps1` 会自动创建）。

---

### 4.6 Go

**Service 库文件**: `<Unit>_abi_service.go`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DefaultAppName`, `DefaultAppDesc` |
| 用户桩 | `internalCall<Api>(uid sys.TP2P_UID, p2pName string, [args]) (T, error)` |
| LingoFuse 回调 | `callback<Api>(inp, out *lingofuse.DataHandle)`（Call）<br>`callback<Api>(inp *lingofuse.DataHandle)`（Notify） |
| 注册 | `RegisterAllABIAPIs(app *lingofuse.AppHandle) error` |
| 注册 | `RegisterAllP2PABIAPIs() error` |
| 便捷 | `CreateAndRegisterABIApp() (*lingofuse.AppHandle, error)` |
| 辅助 | `writeCallbackOK(out)`, `writeCallbackError(out, msg)`, `panicToError(apiName, r)` |

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
    "os"
    abi "<Unit>_abi"
    "github.com/PassByYou888/LingoFuse/go/lingofuse"
    "github.com/PassByYou888/LingoFuse/go/sys"
)

// 1. 填充 internalCall 桩体
//    在 <Unit>_abi_service.go 里直接改 internalCallFoo 的函数体

func main() {
    if err := sys.LoadLibrary(); err != nil {
        fmt.Fprintf(os.Stderr, "[FATAL] %v\n", err)
        os.Exit(1)
    }

    lingofuse.SetOption("Quiet", "True")
    lingofuse.SetOption("ConsoleOutput", "True")
    lingofuse.ResetPrepare()
    lingofuse.PrepareService("ipc:<Unit>_abi", "ipc:<Unit>_abi")

    app, err := abi.CreateAndRegisterABIApp()
    if err != nil {
        fmt.Fprintf(os.Stderr, "[FATAL] %v\n", err)
        os.Exit(1)
    }

    // 可选：注册测试辅助 API
    app.RegisterCall("LF_TEST_WHOAMI", "whoami helper", cbWhoami)
    app.RegisterNotify("LF_TEST_ASK_SERVICE_CALL_ME", "ask", cbAsk)

    // P2P
    lingofuse.SetOption("LF_P2P_name", "<Unit>_service_test_p2p")
    _ = abi.RegisterAllP2PABIAPIs()
    lingofuse.RegisterP2PCall("LF_TEST_WHOAMI", "whoami", cbWhoami)

    if _, err := lingofuse.PrepareClient("ipc:<Unit>_abi", app); err != nil {
        fmt.Fprintf(os.Stderr, "[FATAL] %v\n", err)
        app.Close()
        os.Exit(1)
    }
    ok, err := lingofuse.PrepareDone()
    if err != nil || !ok {
        fmt.Fprintf(os.Stderr, "[FATAL] prepareDone: ok=%v err=%v\n", ok, err)
        lingofuse.ExitMainThread()
        app.Close()
        os.Exit(1)
    }

    fmt.Println("[OK] service ready")
    var dummy string
    fmt.Scanln(&dummy)

    // 3. 关闭
    lingofuse.ExitMainThread()
    app.Close()
    lingofuse.Shutdown()
}

func cbWhoami(inp, out *lingofuse.DataHandle) {
    uid, _ := inp.GetP2PUID()
    p2pName, _ := inp.GetP2PName()
    _ = out.WriteUint8(0x00)
    _ = out.WriteBytes(uid.Bytes[:])
    _ = out.WriteString(p2pName)
}

func cbAsk(inp *lingofuse.DataHandle) {
    // ...
}
```

**注意事项**

- **`sys.LoadLibrary()`**：必须先调用；Go 侧不自动加载运行时。
- **`internalCall<Api>`**：生成器直接写在 `<Unit>_abi_service.go` 里；**直接编辑该文件**填充实现。
- **`panicToError`**：库内部用 `recover()` 捕获桩函数 panic 并转为 error；桩函数即使 panic 也不会崩溃 service。
- **`callback<Api>` 签名**：Call 类型是 `(inp, out *lingofuse.DataHandle)`，Notify 类型是 `(inp *lingofuse.DataHandle)`。
- **`sys.TP2P_UID`**：32 字节 UID 类型。

---

### 4.7 Java

**Service 库文件**: `<Unit>AbiService.java`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `AppInfo.Name`, `AppInfo.Desc`, `STATUS_OK`, `STATUS_ERROR` |
| 用户桩 | `InternalCalls.internal_call_<Api>(P2PUid lfUid, string lfP2PName, [args])` |
| LingoFuse 回调 | `Callbacks.callback_<Api>(DataHandle in, DataHandle out)`（Call）<br>`Callbacks.callback_<Api>(DataHandle in)`（Notify） |
| 注册 | `Service.registerAllAbiApis(AppHandle app)` |
| 注册 | `Service.registerAllP2PAbiApis()` |
| 便捷 | `Service.createAndRegisterAbiApp()` |

**开发平台**

| 项目 | 要求 |
|------|------|
| JDK | 22+（`maven.compiler.release=22`） |
| 构建 | Maven 3.9+ |
| 依赖 | `lingofuse.jar` + `jackson-databind` |

**操作系统**: Windows / Linux / macOS。

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
import lingofuse.AppHandle;
import lingofuse.DataHandle;
import lingofuse.Framework;
import lingofuse.Options;
import lingofuse.P2PRegistry;
import lingofuse.async.AsyncBridge;
import lingofuse.ffi.LibraryLoader;
import <Unit>_abi.<Unit>AbiService;

public class Main {
    public static void main(String[] args) throws Exception {
        LibraryLoader.selectPlatformFileName();

        Framework.resetPrepare();
        Options.setQuiet(true);
        Options.setConsoleOutput(true);

        Framework.prepareService("ipc:<Unit>_abi", "ipc:<Unit>_abi");

        AppHandle app = <Unit>AbiService.createAndRegisterAbiApp();
        if (app == null) { System.exit(1); }

        // 可选：注册测试辅助 API
        app.registerCall("LF_TEST_WHOAMI", "whoami helper", Main::cbWhoami);
        app.registerNotify("LF_TEST_ASK_SERVICE_CALL_ME", "ask", Main::cbAsk);

        // P2P
        Options.setP2pName("<Unit>_service_test_p2p");
        <Unit>AbiService.registerAllP2PAbiApis();
        P2PRegistry.registerCall("LF_TEST_WHOAMI", "whoami", Main::cbWhoami);

        if (Framework.prepareClient("ipc:<Unit>_abi", app) == -1) {
            app.close();
            System.exit(1);
        }
        if (Framework.prepareDone() != 1) {
            Framework.exitMainThread();
            app.close();
            System.exit(1);
        }

        System.out.println("[OK] service ready");
        System.in.read();

        // 3. 关闭
        AsyncBridge.shutdownInstance();
        Framework.exitMainThread();
        app.close();
        Framework.shutdown();
    }

    // 1. 填充 InternalCall 桩体
    public static class InternalCallsOverride {
        public static int InternalCall_Foo(P2PUid lfUid, String lfP2PName, int a, int b) {
            return a + b;
        }
    }

    static void cbWhoami(DataHandle in, DataHandle out) {
        try {
            byte[] uid = in.getP2pUid();
            String p2p = in.getP2pName();
            out.writeInt8((byte) 0);
            out.writeBytes(uid);
            out.writeString(p2p);
        } catch (Throwable t) {
            // ...
        }
    }

    static void cbAsk(DataHandle in) {
        // ...
    }
}
```

**注意事项**

- **`InternalCalls` 类**：生成器**不会**生成 partial 支持（Java 没有 partial 概念）；你需要**直接编辑 `<Unit>AbiService.java`** 里的 `InternalCalls.InternalCall_<Api>` 方法体。
- **`LibraryLoader.selectPlatformFileName()`**：必须先调用，否则 `System.loadLibrary` 找不到运行时。
- **`AppHandle` 需手动 `close()`**：在 `finally` 或关闭流程中确保调用。
- **`AsyncBridge.shutdownInstance()`**：进程退出前必须调用，否则 worker 线程会被挂住。
- **`P2PRegistry`**：P2P 注册通过它完成；`registerCall` / `registerNotify` 是静态方法。

---

### 4.8 Node.js

**Service 库文件**: `<Unit>_abi_service.js`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 用户桩 | `internal_call_<api>(_uid, _p2p, [args])` |
| LingoFuse 回调 | `Cb_<api>(_trigger, input, output)`（Call）<br>`Cb_<api>(_trigger, input)`（Notify） |
| 注册 | `registerAll(app)`（返回失败数） |
| 注册 | `registerAllP2P()`（返回失败数） |
| 回调指针 | `cb_<api>`（`koffi.register(...)` 产生） |

**开发平台**

| 项目 | 要求 |
|------|------|
| Node.js | 18+ |
| FFI | `koffi`（由 `lingofuse-js` 引入） |

**操作系统**: Windows / Linux / macOS。

**依赖**

```bash
npm install lingofuse-js
```

**接入代码**

```javascript
'use strict';
const lf = require('lingofuse-js');
const service = require('./<Unit>_abi_service.js');

lf.loadLibrary();
lf.framework.setOption('Quiet', 'True');
lf.framework.setOption('ConsoleOutput', 'True');

// 1. 填充 internal_call 桩体
const originalFoo = service.internal_call_Foo;
service.internal_call_Foo = function (_uid, _p2p, a, b) {
  return a + b;
};

// 2. 启动 service
const app = new lf.AppHandle('<Unit>_abi', 'ABI service for <Unit>');
const failed = service.registerAll(app.raw);
if (failed !== 0) {
  console.error(`[FATAL] ${failed} registration(s) failed`);
  process.exit(1);
}

// P2P
lf.framework.setOption('LF_P2P_name', '<Unit>_service_test_p2p');
service.registerAllP2P();

lf.framework.resetPrepare();
lf.framework.prepareService('ipc:<Unit>_abi', 'ipc:<Unit>_abi');
lf.framework.prepareClient('ipc:<Unit>_abi', app);
if (lf.framework.prepareDone() !== 1) {
  console.error('[FATAL] prepareDone failed');
  process.exit(1);
}

console.log('[OK] service ready');
setInterval(() => {}, 1 << 30);  // 保持事件循环

process.on('SIGINT', () => {
  lf.AsyncBridge.shutdownInstance();
  lf.framework.exitMainThread();
  app.dispose();
  lf.framework.shutdown();
  process.exit(0);
});
```

**注意事项**

- **无 `createAndRegister` 便捷函数**：Node.js 侧需要**手工** `new lf.AppHandle(...)` + `service.registerAll(app.raw)`。
- **`registerAll` 返回失败数**：`0` 表示全部注册成功；`> 0` 表示有 `N` 个失败。
- **`internal_call_<api>` 桩替换**：直接重新赋值 `service.internal_call_Foo = ...`。
- **`cb_<api>`**：由 `koffi.register(...)` 产生，已由 `registerAll` 内部使用，**不要**手动注册。
- **`lf.AsyncBridge.shutdownInstance()`**：Node.js 进程退出前必须调用，否则 worker 线程会被挂住。

---

### 4.9 TypeScript

**Service 库文件**: `<Unit>_abi_service.ts`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 用户桩 | `internal_call_<api>(args)`（**无 uid / p2p 参数**） |
| LingoFuse 回调 | `Cb_<api>(_trigger, input, output)`（Call）<br>`Cb_<api>(_trigger, input)`（Notify） |
| 注册 | `registerAll(app)`（返回失败数） |
| 注册 | `registerAllP2P()`（返回失败数） |
| 回调指针 | `cb_<api>`（`koffi.register(...)` 产生） |

**开发平台**

| 项目 | 要求 |
|------|------|
| Node.js | 18+ |
| TypeScript | 5.6+ |
| 包 | `lingofuse-ts` |

**操作系统**: Windows / Linux / macOS。

**依赖**

```bash
npm install lingofuse-ts
```

**接入代码**

```typescript
import * as lf from "lingofuse-ts";
import * as service from "./<Unit>_abi_service";

lf.loadLibrary();
lf.framework.setOption("Quiet", "True");
lf.framework.setOption("ConsoleOutput", "True");

// 1. 填充 internal_call 桩体
(service as any).internal_call_Foo = (a: number, b: number): number => a + b;

// 2. 启动 service
const app = new lf.AppHandle("<Unit>_abi", "ABI service for <Unit>");
const failed = service.registerAll(app.raw);
if (failed !== 0) {
  console.error(`[FATAL] ${failed} registration(s) failed`);
  process.exit(1);
}

// P2P
lf.framework.setOption("LF_P2P_name", "<Unit>_service_test_p2p");
service.registerAllP2P();

lf.framework.resetPrepare();
lf.framework.prepareService("ipc:<Unit>_abi", "ipc:<Unit>_abi");
lf.framework.prepareClient("ipc:<Unit>_abi", app);
if (lf.framework.prepareDone() !== 1) {
  console.error("[FATAL] prepareDone failed");
  process.exit(1);
}

console.log("[OK] service ready");
setInterval(() => {}, 1 << 30);

process.on("SIGINT", () => {
  lf.AsyncBridge.shutdownInstance();
  lf.framework.exitMainThread();
  app.dispose();
  lf.framework.shutdown();
  process.exit(0);
});
```

**注意事项**

- **`internal_call_<api>` 签名**：与 Node.js 不同，TypeScript 版本**只接受用户参数**（无 `_uid` / `_p2p`）。
- **`registerAll` / `registerAllP2P`**：返回失败数；`0` 表示全部成功。
- **`koffi.register(Cb_<api>, LfCallFuncPtr)`**：由生成器内部在 `cb_<api>` 字段中完成，用户无需手动干预。

---

### 4.10 Erlang

**Service 库文件**: `<Unit>_abi_service.erl`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `?DEFAULT_APP_NAME`, `?DEFAULT_APP_DESC`（通过 `-define`） |
| 用户桩 | `internal_call_<api>(UID, P2PName, [args])` |
| 分发 | `lf_dispatch_call(Api, Ref, Payload, Identity)` / `lf_dispatch_notify(Api, Payload, Identity)` |
| 注册 | `register_all_apis(AppHnd)` |
| 注册 | `register_all_p2p_apis()` |
| 便捷 | `create_and_register_app()` |
| 解码 | `decode_params_<api>(Bin)` |

**开发平台**

| 项目 | 要求 |
|------|------|
| Erlang/OTP | 27+ |
| 依赖模块 | `lingofuse.beam`（在 `LINGOFUSE_EBIN` 中） |

**操作系统**: Windows / Linux / macOS。

**接入代码**

```erlang
-module(my_service_main).
-export([main/1]).

main(_) ->
    ok = lingofuse:ensure_loaded(),
    ok = lingofuse:set_option(<<"Quiet">>, <<"True">>),
    ok = lingofuse:reset_prepare(),
    {ok, _Tag} = lingofuse:prepare_service(<<"ipc:<Unit>_abi">>, <<"ipc:<Unit>_abi">>),

    {ok, App} = '<Unit>_abi_service':'create_and_register_app'(),
    ok = lingofuse:register_call_sync(App, <<"LF_TEST_WHOAMI">>, <<"whoami">>, self(), #{with_identity => true}),
    ok = lingofuse:register_notify(App, <<"LF_TEST_ASK_SERVICE_CALL_ME">>, <<"ask">>, self(), #{with_identity => true}),

    ok = lingofuse:set_opt_p2p_name(<<"<Unit>_service_test_p2p">>),
    _ = '<Unit>_abi_service':'register_all_p2p_apis'(),

    case lingofuse:prepare_client(<<"ipc:<Unit>_abi">>, App) of
        {ok, _} -> ok;
        _ -> halt(1)
    end,
    {ok, 1} = lingofuse:prepare_done(),

    io:format("[OK] service ready~n"),
    loop(App).

loop(App) ->
    receive
        {lf_call, Ref, Api, Payload, Identity} when is_integer(Ref) ->
            _ = '<Unit>_abi_service':lf_dispatch_call(Api, Ref, Payload, Identity),
            loop(App);
        {lf_call, Ref, Api, Payload} when is_integer(Ref) ->
            _ = '<Unit>_abi_service':lf_dispatch_call(Api, Ref, Payload, #{}),
            loop(App);
        {lf_notify, Api, Payload, Identity} when is_binary(Api) ->
            _ = '<Unit>_abi_service':lf_dispatch_notify(Api, Payload, Identity),
            loop(App);
        {lf_notify, Api, Payload} when is_binary(Api) ->
            _ = '<Unit>_abi_service':lf_dispatch_notify(Api, Payload, #{}),
            loop(App);
        _Other ->
            loop(App)
    end.
```

**注意事项**

- **进程模型**：Erlang service 通常是**主循环** + `receive`；`lf_dispatch_call` / `lf_dispatch_notify` 由生成器提供，负责把 `Api` 映射到对应的 `handle_call_<api>` / `handle_notify_<api>`。
- **`internal_call_<api>` 桩**：生成器写在 `<Unit>_abi_service.erl` 里；**直接编辑该文件**填充实现。
- **`with_identity => true`**：注册时启用 `uid` / `p2p_name` 注入；这是 UID 探测的前提。
- **P2P**：`register_all_p2p_apis()` 内部遍历所有 API 调用 `register_p2p_call` / `register_p2p_notify`。
- **`lf_call` 与 `lf_p2p_call`**：分发时可以区分普通 call 和 P2P call。

---

### 4.11 Julia

**Service 库文件**: `<Unit>_abi_service.jl`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DEFAULT_APP_NAME`, `DEFAULT_APP_DESC` |
| 用户桩 | `internal_call_<api>(uid, p2p_name, [args])` 通过 `_impl` Ref 调度 |
| 桩替换 | `set_internal_call_<api>!(f)` |
| LingoFuse 回调 | `callback_<api>(in_bytes)::Vector{UInt8}`（Call）<br>`callback_<api>(in_bytes)::Nothing`（Notify） |
| 注册 | `register_all_abi_apis!(app)` |
| 注册 | `register_all_p2p_abi_apis!()` |
| 便捷 | `create_and_register_abi_app()` |

**开发平台**

| 项目 | 要求 |
|------|------|
| Julia | 1.9+ |
| 线程 | **必须 `--threads=2`** |

**操作系统**: Windows / Linux / macOS。

**依赖**

- `LingoFuse` Julia 包（`Pkg.develop(path="<LingoFuse>/julia")`）。

**接入代码**

```julia
import LingoFuse
const LF = LingoFuse
include("<Unit>_abi_service.jl")
const svc = <Unit>_abi_service

# 1. 填充 internal_call 桩体
svc.set_internal_call_Foo!((uid, p2p_name, a, b) -> a + b)

# 2. 启动 service
LF.set_option("Quiet", "True")
LF.set_option("ConsoleOutput", "True")
LF.reset_prepare()
LF.prepare_service("ipc:<Unit>_abi", "ipc:<Unit>_abi")

app = svc.create_and_register_abi_app()
if app === nothing
    println("[FATAL] create_and_register_abi_app failed")
    exit(1)
end

LF.set_option("LF_P2P_name", "<Unit>_service_test_p2p")
svc.register_all_p2p_abi_apis!()

rc = LF.prepare_client("ipc:<Unit>_abi", app)
if rc == -1
    println("[FATAL] prepare_client failed")
    exit(1)
end
if LF.prepare_done() != 1
    println("[FATAL] prepare_done failed")
    exit(1)
end

println("[OK] service ready")
try
    while true; sleep(1); end
catch
end

# 3. 关闭
LF.exit_main_thread()
LF.dispose!(app)
LF.shutdown()
```

**注意事项**

- **`--threads=2` 强制**：Julia 的 `Threads.@spawn` 需要至少 2 个线程；启动脚本必须用 `julia --threads=2 ...`。
- **桩替换**：用 `set_internal_call_<api>!(f)` 注入实现；`f` 的签名是 `(uid, p2p_name, [args])`。
- **`callback_<api>`**：生成器已写好，不需要修改。
- **`app` 类型**：`LF.App`。
- **默认 `_internal_call_<api>_default`**：生成器提供一个返回默认值的桩；如果你不调用 `set_internal_call_<api>!`，回调会返回默认值。

---

### 4.12 Zig

**Service 库文件**: `<Unit>_abi_service.zig`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DEFAULT_APP_NAME`, `DEFAULT_APP_DESC` |
| 用户桩 | `internal_call_<api>(uid: lf.Uid, p2p_name: []const u8, [args]) !T` |
| LingoFuse 回调 | `callback_<api>(_ctx, in_: *lf.DataHandle, out_: *lf.DataHandle) lf.Error!void` |
| 注册 | `registerAllAbiApis(app: *lf.AppHandle) !void` |
| 注册 | `registerAllP2pAbiApis() !void` |
| 便捷 | `createAndRegisterAbiApp() !lf.AppHandle` |

**开发平台**

| 项目 | 要求 |
|------|------|
| Zig | 0.17+ |
| 模块 | `lingofuse` Zig 包 |

**操作系统**: Windows / Linux / macOS。

**依赖**

```zig
// build.zig.zon
.dependencies = .{
    .lingofuse = .{ .path = "<LingofuseDir>" },
},
```

**接入代码**

```zig
const std = @import("std");
const lf = @import("lingofuse");
const svc = @import("<Unit>_abi_service");

pub fn main() !void {
    lf.framework.init() catch |err| {
        std.debug.print("[FATAL] init: {}\n", .{err});
        std.Exit(1);
    };
    defer lf.framework.deinit();

    lf.options.setQuiet(true) catch {};
    lf.options.setConsoleOutput(true) catch {};
    lf.framework.resetPrepare();

    _ = lf.framework.prepareService("ipc:<Unit>_abi", "ipc:<Unit>_abi") catch |err| {
        std.debug.print("[FATAL] prepareService: {}\n", .{err});
        std.Exit(1);
    };

    var app = svc.createAndRegisterAbiApp() catch |err| {
        std.debug.print("[FATAL] createAndRegisterAbiApp: {}\n", .{err});
        std.Exit(1);
    };

    lf.options.setP2PName("<Unit>_service_test_p2p") catch {};
    svc.registerAllP2pAbiApis() catch {};

    _ = lf.framework.prepareClient("ipc:<Unit>_abi", &app) catch |err| {
        std.debug.print("[FATAL] prepareClient: {}\n", .{err});
        std.Exit(1);
    };

    if (!lf.framework.prepareDone()) {
        std.debug.print("[FATAL] prepareDone failed\n", .{});
        std.Exit(1);
    }

    std.debug.print("[OK] service ready\n", .{});

    var i: usize = 0;
    while (i < 120) : (i += 1) {
        std.time.sleep(1 * std.time.ns_per_s);
    }

    // 3. 关闭
    lf.framework.exitMainThread();
    app.deinit();
    lf.framework.shutdown();
}
```

**注意事项**

- **`internal_call_<api>` 桩**：生成器写在 `<Unit>_abi_service.zig` 里；**直接编辑该文件**填充实现。
- **`lf.Error`**：包含 `CallFailed` / `ReadFailed` / `OutOfMemory` 等。
- **`callback_<api>`**：生成器内部使用 `w_err` 写错误响应；不要修改。
- **`app.deinit()`**：必须显式调用，否则资源泄漏。

---

### 4.13 Swift

**Service 库文件**: `<Unit>_abi_service.swift`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `defaultAppName`, `defaultAppDesc` |
| 用户桩 | `internalCall_<Api>(uid: Uid, p2pName: String, [args]) -> T`（function）<br>`internalNotify_<Api>(uid: Uid, p2pName: String, [args])`（procedure） |
| LingoFuse 回调 | `callback_<Api>(input: DataHandle, output: DataHandle)`（Call）<br>`callback_<Api>(input: DataHandle)`（Notify） |
| 注册 | `registerAllABIAPIs(app: AppHandle) throws` |
| 注册 | `registerAllP2PABIAPIs() throws` |
| 便捷 | `createAndRegisterABIApp() throws -> AppHandle` |

**开发平台**

| 项目 | 要求 |
|------|------|
| Swift | 5.9+ |
| 平台 | macOS 12+（主要）/ Linux（社区验证）/ Windows（谨慎） |

**操作系统**: macOS（主要）/ Linux / Windows（不推荐生产）。

**依赖**

- `LingoFuse` Swift 包（`Package.swift` 中 `.package(path: "<LingofuseDir>")`）。

**接入代码**

```swift
import Foundation
import LingoFuse
import <Unit>_abi_service

// 1. 填充 internalCall 桩体
//    在 <Unit>_abi_service.swift 里直接改 internalCall_Foo 的函数体

func main() {
    if LF_LoadLibrary() != 1 {
        FileHandle.standardError.write("[FATAL] LF_LoadLibrary failed\n".data(using: .utf8)!)
        exit(1)
    }
    defer { LF_FreeLibrary() }

    Framework.setOption("Quiet", "True")
    Framework.setOption("ConsoleOutput", "True")
    Framework.resetPrepare()

    do {
        try Framework.prepareService(listeningAddr: "ipc:<Unit>_abi",
                                     physicsAddr: "ipc:<Unit>_abi")

        let app = try <Unit>ABIService.createAndRegisterABIApp()

        // 可选：注册测试辅助 API
        try app.registerCall("LF_TEST_WHOAMI", "whoami helper", cbWhoami)
        try app.registerNotify("LF_TEST_ASK_SERVICE_CALL_ME", "ask", cbAsk)

        // P2P
        Options.setP2PName("<Unit>_service_test_p2p")
        try <Unit>ABIService.registerAllP2PABIAPIs()
        try P2P.registerCall("LF_TEST_WHOAMI", description: "whoami", handler: cbWhoami)

        try Framework.prepareClient(physicsAddr: "ipc:<Unit>_abi", app: app)

        if !Framework.prepareDone() {
            Framework.exitMainThread()
            app.dispose()
            Framework.shutdown()
            exit(1)
        }

        print("[OK] service ready")
        _ = readLine()

        // 3. 关闭
        Framework.exitMainThread()
        app.dispose()
        Framework.shutdown()
    } catch {
        FileHandle.standardError.write("[FATAL] \(error)\n".data(using: .utf8)!)
        Framework.shutdown()
        exit(1)
    }
}

func cbWhoami(_ input: DataHandle, _ output: DataHandle) {
    let uid = input.p2pUid()
    let p2p = input.p2pName()
    try? output.writeUInt8(0x00)
    try? output.writeBytes(uid.rawBytes)
    try? output.writeString(p2p)
}

func cbAsk(_ input: DataHandle) {
    // ...
}

main()
```

**注意事项**

- **`internalCall_<Api>` 桩**：生成器写在 `<Unit>_abi_service.swift` 里；**直接编辑该文件**填充实现。
- **`LF_LoadLibrary()`**：必须先调用；Swift 侧不自动加载运行时。
- **`registerCall` / `registerNotify`**：`AppHandle` 的方法，抛异常。
- **`P2P` 命名空间**：P2P 注册通过 `P2P.registerCall` / `P2P.registerNotify` 完成。
- **`Uid` 类型**：`LingoFuse` 包导出的 32 字节 UID；`Uid.null` 是零 UID。

---

### 4.14 Ruby

**Service 库文件**: `<Unit>_abi_service.rb`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DEFAULT_APP_NAME`, `DEFAULT_APP_DESC` |
| 用户桩 | `internal_call_<api>(uid, p2p_name, [args])` |
| LingoFuse 回调 | `callback_<api>(input, output)`（Call）<br>`callback_<api>(input)`（Notify） |
| 注册 | `register_all_abi_apis(app)` |
| 注册 | `register_all_p2p_abi_apis` |
| 便捷 | `create_and_register_abi_app` |
| 辅助 | `safe_uid(input)`, `safe_p2p_name(input)` |

**开发平台**

| 项目 | 要求 |
|------|------|
| Ruby | 3.0+ |
| Gem | `lingofuse` |

**操作系统**: Windows / Linux / macOS。

**依赖**

```bash
gem install lingofuse
```

**接入代码**

```ruby
require 'lingofuse'
require_relative '<Unit>_abi_service'

# 1. 填充 internal_call 桩体
module <Unit>_abi
  module Service
    def self.internal_call_Foo(uid, p2p_name, a, b)
      a + b
    end
  end
end

LingoFuse::Options.set_opt_quiet(true)

# 2. 启动 service
LingoFuse::Framework.reset_prepare
LingoFuse::Framework.prepare_service('ipc:<Unit>_abi', 'ipc:<Unit>_abi')

app = <Unit>_abi::Service.create_and_register_abi_app
if app.nil?
  puts '[FATAL] create_and_register_abi_app failed'
  exit 1
end

# 可选：注册测试辅助 API
app.register_call('LF_TEST_WHOAMI', 'whoami helper', &method(:cb_whoami))
app.register_notify('LF_TEST_ASK_SERVICE_CALL_ME', 'ask', &method(:cb_ask))

# P2P
LingoFuse::Options.set_opt_p2p_name('<Unit>_service_test_p2p')
<Unit>_abi::Service.register_all_p2p_abi_apis

LingoFuse::Framework.prepare_client('ipc:<Unit>_abi', app)
unless LingoFuse::Framework.prepare_done
  puts '[FATAL] prepare_done failed'
  exit 1
end

puts '[OK] service ready'
$stdin.gets

# 3. 关闭
app.dispose
LingoFuse::Framework.exit_main_thread
LingoFuse::Framework.shutdown

def cb_whoami(input, output)
  uid = input.p2p_uid || ("\x00" * 32).b
  p2p = input.p2p_name || ''
  output.write_uint8(0x00)
  output.write_bytes(uid)
  output.write_string(p2p)
end

def cb_ask(input)
  # ...
end
```

**注意事项**

- **`internal_call_<api>` 桩**：生成器写在 `<Unit>_abi_service.rb` 里；**直接编辑该文件**填充实现。
- **`create_and_register_abi_app`**：返回 `AppHandle` 实例。
- **`register_call` / `register_notify`**：`AppHandle` 实例方法，接受 `&block` 或 `&method(:cb)`。
- **`safe_uid` / `safe_p2p_name`**：生成器提供的辅助函数，处理 nil 边界情况。

---

### 4.15 Fortran

**Service 库文件**: `<Unit>_abi_service.f90`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DEFAULT_APP_NAME`, `DEFAULT_APP_DESC`, `ABI_STATUS_OK`, `ABI_STATUS_ERROR` |
| 用户桩 | `internal_call_<api>(uid, p2p_name, [args]) result(ret)`（function）<br>`internal_call_<api>(uid, p2p_name, [args])`（subroutine） |
| LingoFuse 回调 | `<api>_callback(input, output) bind(C)`（Call）<br>`<api>_callback(input) bind(C)`（Notify） |
| 注册 | `register_all_abi_apis(app) result(failed_count)` |
| 注册 | `register_all_p2p_abi_apis() result(failed_count)` |
| 便捷 | `create_and_register_abi_app() result(app)` |

**开发平台**

| 项目 | 要求 |
|------|------|
| 编译器 | gfortran 9+ + gcc 9+ + g++ 9+ |
| 模块 | `lf_fortran_mod` |

**操作系统**: Windows / Linux / macOS。

**依赖**

| 依赖 | 引入方式 |
|------|----------|
| `lf_fortran_mod.f90` | 编译进项目 |
| `LingoFuse.c` | 编译进项目 |
| `lf_fortran.cpp` | 编译进项目 |
| `LingoFuse64.dll` / `z_ipc_64.dll` | 可执行文件同目录 |

**接入代码**

```fortran
program my_service_main
  use iso_c_binding
  use lf_fortran_mod
  use <Unit>_abi_service
  implicit none

  type(c_ptr) :: app
  integer(c_int) :: failed_count
  integer(c_int) :: lf_rc

  call lf_load_library()
  call lf_set_opt_quiet(.true.)
  call lf_set_opt_console_output(.true.)
  call lf_reset_prepare()
  call lf_prepare_service('ipc:<Unit>_abi', 'ipc:<Unit>_abi')

  app = create_and_register_abi_app()
  if (.not. c_associated(app)) then
    print *, '[FATAL] create_and_register_abi_app failed'
    stop 1
  end if

  failed_count = register_all_p2p_abi_apis()
  call lf_set_opt_p2p_name('<Unit>_service_test_p2p')

  lf_rc = lf_prepare_client('ipc:<Unit>_abi', app)
  if (lf_rc < 0) then
    print *, '[FATAL] prepare_client failed'
    call cleanup()
    stop 1
  end if

  lf_rc = lf_prepare_done()
  if (lf_rc /= 1) then
    print *, '[FATAL] prepare_done failed'
    call cleanup()
    stop 1
  end if

  print *, '[OK] service ready'

  ! 等待（例如 30 秒后自动停止，或按 Ctrl+C）
  call lf_sleep_ms(30000_c_int32_t)

  call cleanup()
  print *, '[SHUTDOWN]'

contains

  ! 1. 填充 internal_call 桩体
  function internal_call_Foo(uid, p2p_name, a, b) result(ret)
    integer(c_int8_t), intent(in) :: uid(LF_UID_BYTE_COUNT)
    character(len=*), intent(in) :: p2p_name
    integer(c_int32_t), intent(in) :: a, b
    integer(c_int32_t) :: ret

    ret = a + b
  end function

  subroutine cleanup()
    call lf_exit_main_thread()
    if (c_associated(app)) then
      call lf_app_destroy(app)
      app = c_null_ptr
    end if
    call lf_shutdown()
    call lf_free_library()
  end subroutine

end program my_service_main
```

**注意事项**

- **`internal_call_<api>` 桩**：生成器写在 `<Unit>_abi_service.f90` 里；**直接编辑该文件**填充实现。
- **`<api>_callback`（不是 `callback_<api>`）**：Fortran 的回调命名是 **`<api>_callback`**（`bind(C)`），由 `create_and_register_abi_app` 内部 `c_funloc` 注册。
- **`register_all_abi_apis` / `register_all_p2p_abi_apis` 返回 `failed_count`**：`0` 表示全部成功。
- **`lf_fortran_mod`**：Fortran 侧所有 `lf_*` 函数都由此模块导出。
- **`LF_UID_BYTE_COUNT`**：32，UID 的字节数。

---

### 4.16 Dart

**Service 库文件**: `<Unit>_abi_service.dart`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DEFAULT_APP_NAME`, `DEFAULT_APP_DESC`, `STATUS_OK`, `STATUS_ERROR` |
| 用户桩 | `internal_call_<api>([args])`（**无 uid / p2p 参数**） |
| LingoFuse 回调 | `callback_<api>(CallContext ctx)`（统一签名） |
| 注册 | `register_all_abi_apis(AppHandle app)` |
| 注册 | `register_all_p2p_abi_apis()` |
| 便捷 | `create_and_register_abi_app()` |
| 辅助 | `lf_get_call_stats()` |

**开发平台**

| 项目 | 要求 |
|------|------|
| Dart | 3.0+ |
| 桥 | `lf_dart_bridge.dll` / `.so` / `.dylib` |
| 包 | `lingofuse` Dart 包 |

**操作系统**: Windows / Linux / macOS。

**接入代码**

```dart
import 'dart:typed_data';
import 'package:lingofuse/lingofuse.dart';
import '<Unit>_abi_service.dart' as svc;

Future<void> main() async {
  await BridgeHost.start();
  Framework.setOptQuiet(true);

  // 1. 填充 internal_call 桩体
  //    在 <Unit>_abi_service.dart 里直接改 internal_call_Foo 的函数体

  // 2. 启动 service
  final app = svc.create_and_register_abi_app();
  if (app == null) {
    stderr.writeln('[FATAL] create_and_register_abi_app failed');
    exit(1);
  }

  svc.register_all_p2p_abi_apis();
  Framework.setOptP2PName('<Unit>_service_test_p2p');

  final tag = Framework.prepareService('ipc:<Unit>_abi', 'ipc:<Unit>_abi');
  if (tag < 0) { exit(1); }

  final ctag = Framework.prepareClient('ipc:<Unit>_abi', app: app);
  if (ctag < 0) { exit(1); }

  if (!Framework.prepareDone()) {
    exit(1);
  }

  print('[OK] service ready');
  await _waitForShutdown();

  // 3. 关闭
  try { Framework.exitMainThread(); } catch (_) {}
  try { app.dispose(); } catch (_) {}
  try { Framework.shutdown(); } catch (_) {}
  try { BridgeHost.instance.stop(); } catch (_) {}
}

Future<void> _waitForShutdown() async {
  final done = Completer<void>();
  final sigint = ProcessSignal.sigint.watch().listen((_) {
    if (!done.isCompleted) done.complete();
  });
  try {
    await done.future;
  } finally {
    await sigint.cancel();
  }
}
```

**注意事项**

- **`internal_call_<api>` 签名**：与 TypeScript 一样，**只接受用户参数**（无 `_uid` / `_p2p`）。
- **`callback_<api>(CallContext ctx)`**：统一签名；`ctx.payload` 是请求字节，`ctx.senderUid` / `ctx.senderP2PName` 是身份信息，回调**返回 `Uint8List`** 作为响应。
- **`lf_get_call_stats()`**：生成器提供的辅助函数，返回 `Map<String, int>`，记录每个 API 的调用次数（用于测试验证）。
- **`BridgeHost.start()`**：必须先调用；`BridgeHost.instance.stop()` 在退出前必须调用。

---

### 4.17 R

**Service 库文件**: `<Unit>_abi_service.R`

**生成的 API 表面**

| 类别 | 名称 |
|------|------|
| 常量 | `DEFAULT_APP_NAME`, `DEFAULT_APP_DESC`, `STATUS_OK`, `STATUS_ERROR` |
| 用户桩 | `internal_call_<api>(lf_uid, lf_p2p_name, [args])` |
| LingoFuse 回调 | `callback_<api>(input_raw, ctx)` |
| 注册 | `register_all_abi_apis(app)` |
| 注册 | `register_all_p2p_abi_apis()` |
| 便捷 | `create_and_register_abi_app()` |
| 序列化 | `abi_pack_int32` / `abi_read_int32` / `abi_write_ok_int32` / ... 全套 |

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
| `LingoFuse64.dll` / `z_ipc_64.dll` | `Sys.setenv(LINGOFUSE_RUNTIME = '<path>')` |

**接入代码**

```r
library(lingofuse)
source("<Unit>_abi_service.R")

# 加载运行时
runtime_dir <- find_runtime()
lf_load(runtime_dir)

# 1. 填充 internal_call 桩体
internal_call_Foo <- function(lf_uid, lf_p2p_name, a, b) {
  a + b
}

# 2. 启动 service
lf_set_opt_quiet(TRUE)
lf_set_opt_console_output(TRUE)

endpoint <- sprintf("ipc:%s", DEFAULT_APP_NAME)
lf_prepare_service(endpoint, endpoint)

service_app <- lf_create_app(DEFAULT_APP_NAME, DEFAULT_APP_DESC)
if (is.null(service_app)) {
  stop("lf_create_app returned NULL")
}

register_all_abi_apis(service_app)

# P2P
lf_set_opt_p2p_name("<Unit>_service_test_p2p")
register_all_p2p_abi_apis()

lf_prepare_client(endpoint, service_app)
if (lf_prepare_done() != 1) {
  stop("lf_prepare_done failed")
}

cat("[READY]\n")
idle_timeout_sec <- 30
last_activity <- Sys.time()
while (TRUE) {
  handled <- lf_poll(50)
  if (isTRUE(handled)) {
    last_activity <- Sys.time()
  }
  idle_sec <- as.numeric(difftime(Sys.time(), last_activity, units = "secs"))
  if (idle_sec > idle_timeout_sec) break
}

# 3. 关闭
lf_cleanup(service_app)
```

**注意事项**

- **`internal_call_<api>` 桩**：生成器写在 `<Unit>_abi_service.R` 里；**直接编辑该文件**填充实现。
- **`callback_<api>(input_raw, ctx)`**：生成器已写好；`input_raw` 是 `raw` 类型（字节向量），`ctx` 是包含 `sender_uid` / `sender_p2p_name` 的 list。
- **`lf_poll(50)`**：非阻塞轮询；`handled` 为 `TRUE` 表示处理了至少一个请求。
- **`find_runtime()`**：由 `lingofuse` 包提供；`Sys.setenv(LINGOFUSE_RUNTIME=...)` 可覆盖。
- **`bit64`**：`int64` / `uint64` 参数或返回值需要 `bit64` 包；缺失时 `internal_call` 内部会 `stop()`。

---

## 5. Service 与 Call 的协作注意事项

### 5.1 端点一致性

| 项目 | service 侧 | call 侧 |
|------|-----------|---------|
| 端点 | `ipc:<Unit>_abi` | `ipc:<Unit>_abi` |
| App 名 | `DEFAULT_APP_NAME = "<Unit>_abi"` | `ABI_TargetApp = "<Unit>_abi"` |
| P2P 组 | `LF_Set_Opt_P2P_Name("<Unit>_service_test_p2p")` | `ABI_TargetP2P = "<Unit>_service_test_p2p"` |

**任一项不一致都会导致 `EABI_RemoteError: nil response (timeout or target not found)`。**

### 5.2 UID 探测

`LF_TEST_WHOAMI` + `LF_TEST_ASK_SERVICE_CALL_ME` 是 call 侧获取 service UID 的**协作协议**：

1. call 侧发出 `LF_TEST_WHOAMI` 请求；
2. service 侧回调返回自己的 UID；
3. call 侧把 UID 缓存起来，用于后续 `_UID_Call` 变体。

**如果 service 侧没有注册 `LF_TEST_WHOAMI` 和 `LF_TEST_ASK_SERVICE_CALL_ME`**：

- `_UID_Call` / `_UID_Async` / `_UID_AsyncSequenced` 变体会全部 `[SKIP]`；
- 其他变体（App / P2P）不受影响。

### 5.3 反向调用（service → client）

`LF_TEST_ASK_SERVICE_CALL_ME` 是 service **主动调用** client 的协作协议：

1. call 侧发起 `LF_TEST_ASK_SERVICE_CALL_ME` 通知；
2. service 侧回调**不立即返回**，而是向 client 发起 `LF_TEST_REPORT_SERVICE_IDENTITY` 调用；
3. client 侧回调收到请求，返回自己的身份信息；
4. service 侧拿到 client 的 UID / P2P 名（用于反向调用）。

**这个协议依赖 call 侧注册了 `LF_TEST_REPORT_SERVICE_IDENTITY` 回调**；如果 call 侧没有注册，service 的反向调用会超时，但**不影响** call 侧的 `_UID_Call` 变体（UID 已在第 2 步通过 `LF_TEST_WHOAMI` 取得）。

### 5.4 线程模型对照

| 场景 | Service 侧 | Call 侧 |
|------|-----------|---------|
| App / P2P / UID 同步调用 | — | 用户线程 |
| App / P2P / UID 异步调用 | — | 用户线程发起，回调在 worker 线程 |
| Service 回调 | worker 线程 | — |
| Service 反向调用 client | 回调内部（worker 线程） | 由 LingoFuse 路由到 client 的回调 |

**关键约束**：**回调内不要调用阻塞的 LingoFuse 接口**。若 service 回调需要主动调用另一个 service，必须：

1. 把调用投递到独立线程（`std::thread` / `Task.Run` / `TThread.CreateAnonymousThread` / `spawn` / `Threads.@spawn`）；
2. 或在回调内只做 `LF_Register*` 的"注册再调用"模式（部分语言支持）。

### 5.5 生命周期顺序

**service 侧**：

```
LF_ResetPrepare
  → LF_PrepareService
  → LF_CreateApp
  → Register_All_ABI_APIs
  → LF_RegisterCall / Notify (辅助 API)
  → LF_Set_Opt_P2P_Name + Register_All_P2P_ABI_APIs
  → LF_PrepareClient
  → LF_PrepareDone
  → [事件循环]
  → LF_ExitMainThread
  → LF_FreeApp
  → LF_Shutdown
```

**call 侧**：

```
LF_ResetPrepare
  → LF_PrepareClient
  → LF_PrepareDone
  → [调用 API]
  → LF_ExitMainThread
  → LF_Shutdown
```

**顺序错误**（例如先 `LF_PrepareDone` 后 `LF_PrepareClient`）会导致 `prepareDone` 返回非 1。

---

## 6. 常见问题

### Q1: Service 库和 Call 库有什么区别？

**Service 库**是**被动响应**端：注册 API、解码请求、调用 `internal_call_<Api>` 桩、编码响应。**Call 库**是**主动发起**端：暴露 `Foo` / `Foo_Async` 等函数供用户调用。

一个完整的双向通信需要**两端都运行**：service 进程启动后监听端点，call 进程连接端点并发起请求。

### Q2: `internal_call_<Api>` 桩必须实现吗？

**必须**。生成器输出的是**返回默认值**的占位桩；不填充就会返回 `0` / `0.0` / `""` / `null`，业务逻辑不会执行。

- **Pascal / C++ / Rust / Go / Java / Zig / Swift / Ruby / Fortran / R**：直接编辑生成的源文件填充桩体；
- **Python / Node.js / TypeScript / Julia**：通过**重新赋值 / 注册函数**替换桩体（不改源文件）；
- **C#**：在 partial class `InternalCalls` 中填充（需另建文件）；
- **Dart**：直接编辑生成的 `.dart` 文件。

### Q3: Service 回调能在主线程执行吗？

**不能**。LingoFuse 的 worker 模型要求回调在 worker 线程执行；如果回调内需要访问 UI 或非线程安全资源，必须**切回主线程**（各语言方法见 `code_decl_to_abi_CALL_LIBRARY_INTEGRATION.md` §4.5）。

### Q4: `Register_All_ABI_APIs` 里做了什么？

它遍历所有 API，对每个 API 调用 `LF_RegisterCall`（function）或 `LF_RegisterNotify`（procedure），参数是：

- `App`：`LF_CreateApp` 返回的句柄；
- `ApiName`：生成器用 `MakeApiName` 规范化后的名字；
- `Description`：从源注释提取的第一行（截断到 200 字符）；
- `UserData`：`nil` / `null`；
- `Callback`：`Callback_<Api>` 函数指针。

返回值是**失败数**（C++ / Go / Java / R）或**副作用**（Pascal / Python / Ruby 等无返回值）。

### Q5: 为什么要注册 `LF_TEST_WHOAMI` 和 `LF_TEST_ASK_SERVICE_CALL_ME`？

它们是 call 侧取得 service UID 的**协作协议**（见 §5.2）。**生产环境中可以省略**，但**测试环境中建议注册**，否则 call 侧的 `_UID_*` 变体会全部 SKIP，覆盖度降低。

### Q6: Service 侧能否调用其他 service？

**可以**，但**不能在回调内同步调用**（会死锁）。正确做法：

1. 回调内把请求**投递到独立线程**；
2. 独立线程中使用 `LF_Call` / `LF_Notify` 调用目标 service；
3. 结果通过线程安全的队列 / Future / Promise 传回。

部分语言（Python / Node.js / Dart / Julia）的 async 模型天然适合这种"回调内 async 调用"模式，但**仍不建议**直接在 worker 线程内发起阻塞调用。

### Q7: 多语言混合部署时，service 需要改什么？

**不需要改**。线协议语言无关，任何语言的 service 都能被任何语言的 call 调用。只需要：

- 两端由**同一源 unit** 生成；
- 端点、App 名、P2P 组名一致；
- 运行时库匹配。

### Q8: Service 库是否支持"只注册一部分 API"？

**支持**。你可以手动调用 `LF_RegisterCall` / `LF_RegisterNotify` 只注册部分 API，而不调用 `Register_All_ABI_APIs`。但需要注意：

- 漏注册的 API 在 call 侧会超时；
- 手动注册需要自己管理 `Callback_<Api>` 的指针生命周期（C# / Node.js 尤其要注意 GC）。

### Q9: Service 启动后如何确认监听成功？

- 观察 `LF_PrepareDone` 返回值：`1` 表示就绪；
- 观察日志 `[OK] service ready`；
- call 侧调用 `LF_CheckApp(<Unit>_abi)` 返回 `True` 表示 service 可见。

### Q10: Swift 在 Windows 上能用于生产吗？

**不推荐**。Swift 5.9+ 官方提供 Windows 工具链，但：

- `LingoFuse` Swift 包当前主要在 macOS 与 Linux 上验证；
- 生产环境建议 macOS（首选）/ Linux（次选）；
- Windows 上优先使用 C++ / C# 作为 service 侧。

---

**文档版本**: 1.0
**文档定位**: `code_decl_to_abi` 生成的 17 种目标语言的 **Service 库**接入指南 —— 覆盖生命周期、回调线程模型、每个语言的 API 表面、开发平台、操作系统、依赖、最小接入代码、与 Call 库的协作注意事项。
**配套文档**: `code_decl_to_abi_USER_GUIDE.md`（端到端用户指南）、`code_decl_to_abi_TESTING_GUIDE.md`（测试方法）、`code_decl_to_abi_CALL_LIBRARY_INTEGRATION.md`（Call 库接入）、`code_decl_to_abi_OPERATIONS.md`（内部实现与扩展）。
**生成代码语言**: 英文。本文档语言: 中文。
