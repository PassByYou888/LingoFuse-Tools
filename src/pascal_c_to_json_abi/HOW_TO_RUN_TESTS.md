# 各语言测试方法指南

> 本文档给出 **每种目标语言** 的测试运行方法。
>
> **三条通用前提**：
>
> 1. **桥接程序（`bridge.py` / `bridge.exe`）必须始终运行**。
> 2. **服务侧必须已启动并在线**。
> 3. **调用侧必须在桥接程序就绪之后启动**。
>
> 测试驱动文件的命名遵循 `<UnitName>_http_json_<side>_main_test___.<ext>` 规则。完整产物清单以生成器返回为准。
>
> **本文档不覆盖"如何构建产物"** —— 构建步骤见 `BUILD_GUIDE.md`（或第 14 章）。本文档只覆盖 **"产物已经构建好、如何运行测试"**。

---

## 目录

1. [通用三进程布局](#1-通用三进程布局)
2. [通用测试清单](#2-通用测试清单)
3. [Pascal](#3-pascal)
4. [Python](#4-python)
5. [C++](#5-c)
6. [C#](#6-c)
7. [JavaScript（浏览器）](#7-javascript浏览器)
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
23. [通用故障排查](#23-通用故障排查)

---

## 1. 通用三进程布局

任何语言的端到端测试都遵循同一个三进程模型：

```
┌──────────────────────────────────────────────────────────────┐
│ 终端 1：服务侧                                                │
│   启动生成的服务（Pascal / Python / C++ / C# / Rust / ...）  │
│   监听 ipc:<UnitName>_http_json                              │
└──────────────────────────────────────────────────────────────┘
                            ▲
                            │ LF_Call
┌──────────────────────────────────────────────────────────────┐
│ 终端 2：桥接程序                                              │
│   python3 bridge.py --endpoint ipc:<UnitName>_http_json \    │
│                     --port 8081 --no-precheck                │
│   必须前台常驻                                                │
└──────────────────────────────────────────────────────────────┘
                            ▲
                            │ HTTP POST
┌──────────────────────────────────────────────────────────────┐
│ 终端 3：调用侧（测试驱动）                                     │
│   运行生成的调用侧测试驱动                                    │
│   打印 OK / FAILED，最终 exit code 0 或 1                    │
└──────────────────────────────────────────────────────────────┘
```

**启动顺序必须严格遵守**：服务 → 桥接程序 → 调用侧。

**关闭顺序**：调用侧 → 桥接程序 → 服务。

### 1.1 端点命名约定

| 名称 | 值 |
|------|-----|
| LingoFuse 端点 | `ipc:<UnitName>_http_json` |
| 默认桥接 HTTP 端口 | `8081` |
| 默认 Base URL | `http://127.0.0.1:8081/<UnitName>` |
| 默认桥接 App 名 | `__lf_http_bridge__` |
| 默认桥接 API 名 | `__lf_outbound_post__` |

`<UnitName>` 是源单元解析后得到的规范化单元名（例如 `unit Calculator;` → `Calculator`）。

---

## 2. 通用测试清单

每种语言的测试驱动都做同样的事：

1. 初始化（连接桥接程序所需的 LingoFuse 客户端 / HTTP 客户端）。
2. 对每个支持的 API 依次执行：
   - **同步**调用；
   - **异步**调用（如语言支持）。
3. 每个调用打印 `OK` 或 `FAILED: <原因>`。
4. 打印汇总：`Passed: N` / `Failed: M`。
5. 以 `0` 退出（全成功）或 `1` 退出（有失败）。

**测试驱动文件名**：`<UnitName>_http_json_<side>_main_test___.<ext>`

- `<side>` = `service` 或 `call`。
- `<ext>` = 见各语言小节。

**测试模式**：

| 模式 | 含义 | 是否需要桥接程序 | 是否需要服务 |
|------|------|:----------------:|:------------:|
| **默认模式** | 服务启动 + 阻塞 | ❌ | ❌ |
| **`--smoke` 模式** | 进程内 LocalCall 自测 | ❌ | ❌（进程内） |
| **调用侧测试** | 走完整 HTTP 链路 | ✅ **必须** | ✅ **必须** |

---

## 3. Pascal

### 3.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service_unit.pas` | Pascal 服务单元 |
| `<Unit>_http_json_call_unit.pas` | Pascal 调用单元 |
| `<Unit>_http_json_service_main_test___.pas` | 服务侧测试驱动 |
| `<Unit>_http_json_call_main_test___.pas` | 调用侧测试驱动 |

### 3.2 前置依赖

- FPC 3.2+ 或 Delphi 11+。
- `lingofuse_import.pas`、`Z.Core`、`Z.PascalStrings`、`Z.UPascalStrings`、`Z.Json`、`Z.UnicodeMixedLib`。
- `LingoFuse64.dll`（或 `liblingofuse.so` / `liblingofuse.dylib`）。
- `z_ipc_64.dll`。

### 3.3 编译测试驱动

**服务侧测试驱动**：

```bash
fpc -Fu<path-to-ZCore> -Fu<path-to-ZNetV2> \
    -Fu<path-to-generated> \
    <Unit>_http_json_service_main_test___.pas
```

**调用侧测试驱动**：

```bash
fpc -Fu<path-to-ZCore> -Fu<path-to-ZNetV2> \
    -Fu<path-to-generated> \
    <Unit>_http_json_call_main_test___.pas
```

### 3.4 运行测试

**服务侧**：

```bash
./<Unit>_http_json_service_main_test___
# 或默认模式
./<Unit>_http_json_service_main_test___
# 或 --smoke 模式（进程内 LocalCall 自测）
./<Unit>_http_json_service_main_test___ --smoke
```

**调用侧**：

```bash
./<Unit>_http_json_call_main_test___
# 覆盖 Base URL
./<Unit>_http_json_call_main_test___ http://10.0.0.5:8081/<Unit>
```

### 3.5 预期输出（调用侧）

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

### 3.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Fatal: Can't find unit Z.Core` | `-Fu` 路径没配 | 加 `-Fu<ZCore 路径>` |
| `LF_PrepareClient returned -1` | 桥接程序未启动或端点不一致 | 检查桥接终端与 `--endpoint` |
| `EHTTPCallError: Network error` | 桥接程序未运行 | 启动桥接程序 |
| `3029 function header doesn't match` | FPC 重载冲突 | 检查生成单元与测试驱动的重载声明 |

---

## 4. Python

### 4.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service.py` | Python 服务 |
| `<Unit>_http_json_call.py` | Python 调用模块 |
| `<Unit>_http_json_service_main_test___.py` | 服务侧测试驱动 |
| `<Unit>_http_json_call_main_test___.py` | 调用侧测试驱动 |

### 4.2 前置依赖

```bash
# 调用侧
pip install requests

# 服务侧
pip install <path-to-LingoFuse>/python
```

### 4.3 运行测试

**服务侧**：

```bash
python3 <Unit>_http_json_service_main_test___.py
# 或 --smoke 模式（进程内 LocalCall，无需桥接）
python3 <Unit>_http_json_service_main_test___.py --smoke
```

**调用侧**：

```bash
python3 <Unit>_http_json_call_main_test___.py
# 覆盖 Base URL
python3 <Unit>_http_json_call_main_test___.py http://10.0.0.5:8081/<Unit>
```

### 4.4 预期输出（调用侧）

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

### 4.5 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `ModuleNotFoundError: requests` | 未安装 | `pip install requests` |
| `ModuleNotFoundError: lingofuse` | 未安装 LingoFuse Python 包 | 装 LingoFuse 发行版 |
| `HTTPCallError: Network error` | 桥接程序未运行 | 启动桥接程序 |
| `asyncio: Task was destroyed` | 异步任务未 await 完 | 用 `asyncio.run(main())` 包裹 |

---

## 5. C++

### 5.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service.hpp` + `.cpp` | C++ 服务 |
| `<Unit>_http_json_call.hpp` + `.cpp` | C++ 调用 |
| `CMakeLists.txt` | 构建脚本 |
| `test_main___.cpp` | 调用侧测试驱动 |

### 5.2 前置依赖

- CMake 3.15+。
- C 与 C++ 编译器（MSVC / g++ / clang++）。
- LingoFuse C++ 发行目录（含 `LingoFuse.h`、`LingoFuse.c`、`LingoFuse.hpp`、`lf_io.hpp`、`lf_http_bridge_client.hpp`、`json.hpp`）。

### 5.3 构建

```bash
# 确保 <Unit>_http_json_service.hpp/.cpp、<Unit>_http_json_call.hpp/.cpp、
# CMakeLists.txt、test_main___.cpp 都在同一目录。
cd <that-directory>

cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

构建产出两个可执行文件：

- `<Unit>_http_json_service`（服务侧）
- `<Unit>_http_json_call_test`（调用侧测试驱动）

### 5.4 运行测试

**服务侧**：

```bash
./build/<Unit>_http_json_service
```

**调用侧**：

```bash
./build/<Unit>_http_json_call_test
```

**Windows**：先复制 `LingoFuse64.dll` 与 `z_ipc_64.dll` 到 `build/Release/`。

```cmd
copy C:\LingoFuse\cpp\LingoFuse64.dll build\Release\
copy C:\LingoFuse\cpp\z_ipc_64.dll build\Release\
build\Release\<Unit>_http_json_call_test.exe
```

### 5.5 预期输出（调用侧）

```
=== Calculator HTTP/JSON call test ===
Base URL: http://127.0.0.1:8081/Calculator

  Add [sync] : OK
  Add [async]: OK
  Sub [sync] : OK
  Sub [async]: OK

all calls succeeded
```

### 5.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Cannot determine link language` | `project()` 只声明 `CXX` | 声明 `C CXX` |
| `LINGOFUSE_CPP_LIB_DIR does not point at a LingoFuse C++ library directory` | 未传 `-DLINGOFUSE_CPP_LIB_DIR` | 传参 |
| 链接器找不到 `LingoFuse` | DLL 未复制 | 复制到可执行文件旁 |
| `HTTPCallError: ... (code=-1, http_status=0)` | 桥接程序未运行 | 启动桥接程序 |

---

## 6. C#

### 6.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service.cs` | C# 服务模块 |
| `<Unit>_http_json_call.cs` | C# 调用模块 |
| `<Unit>_http_json_service_main_test___.cs` | 服务侧测试驱动 |
| `<Unit>_http_json_call_main_test___.cs` | 调用侧测试驱动 |

### 6.2 前置依赖

- .NET 8.0+。
- LingoFuse .NET 绑定（`LingoFuse.dll`）。
- LingoFuse 原生库（`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`）与 `z_ipc_*`。

### 6.3 构建与运行（服务侧）

```bash
dotnet new console -o my_service
cd my_service
cp ../<Unit>_http_json_service.cs .
cp ../<Unit>_http_json_service_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
# 或 --smoke 模式
dotnet run -- --smoke
```

### 6.4 构建与运行（调用侧）

```bash
dotnet new console -o my_call
cd my_call
cp ../<Unit>_http_json_call.cs .
cp ../<Unit>_http_json_call_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

### 6.5 预期输出（调用侧）

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

### 6.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `DllNotFoundException: LingoFuse64` | DLL 未复制 | 复制到 bin 目录 |
| `Could not load type 'lingofuse.AppHandle'` | LingoFuse.dll 引用缺失 | `dotnet add reference` |
| `HTTPCallError` | 桥接程序未运行 | 启动桥接程序 |
| `PrepareDone returned 0` | 同一进程已调用过 `PrepareDone` | 重启进程 |

---

## 7. JavaScript（浏览器）

### 7.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_call.js` | 浏览器 JS 客户端（IIFE） |
| `<Unit>_http_json_call_test.html` | 自包含测试页 |

### 7.2 前置依赖

现代浏览器（Chrome / Edge / Firefox / Safari）。**无第三方依赖**。

### 7.3 运行测试

**方式 A：双击 `*_test.html`**

直接双击打开。

**方式 B：通过 HTTP 服务提供（推荐）**

```bash
cd <generated-directory>
python3 -m http.server 9000
# 打开 http://127.0.0.1:9000/<Unit>_http_json_call_test.html
```

**方式 C：在你自己的页面里引入**

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

### 7.4 预期输出（HTML 测试页）

每个 API 卡片显示 `OK: <result>` 或 `Error: <message>`。顶部 banner 显示：
- `Page ready. Base URL: http://127.0.0.1:8081/<Unit>`
- `Last call: <Api> succeeded.` / `Last call: <Api> failed: ...`

### 7.5 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Failed to fetch` | 桥接程序未运行，或 CORS | 启动桥接；桥接需返回 `Access-Control-Allow-Origin: *` |
| `file://` 下打开报 CORS | 浏览器的 `file://` 限制 | 用 `python3 -m http.server 9000` 提供 |
| `Mixed Content` | 页面 https，桥接 http | 用 http 提供页面，或给桥接配 https |
| `Add is not a function` | `window.<Unit>Api` 未就绪 | 检查 `<script src>` 路径；等 `DOMContentLoaded` 后再调 |

---

## 8. Node.js

### 8.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service_node.js` | Node.js 服务 |
| `<Unit>_http_json_call_node.js` | Node.js 调用模块 |
| `<Unit>_http_json_service_main_test___.js` | 服务侧测试驱动 |
| `<Unit>_http_json_call_main_test___.js` | 调用侧测试驱动 |
| `setup_js_tests.ps1` | 环境准备脚本 |

### 8.2 前置依赖

- Node.js 18+（`fetch` 内置）。
- `lingofuse-js`（服务侧）。

### 8.3 准备环境（推荐）

```powershell
.\setup_js_tests.ps1 -JsLibDir D:\LingoFuse\js\lingofuse-js -RunSmoke
```

**手动**：

```bash
npm install lingofuse-js
```

### 8.4 运行测试

**服务侧**：

```bash
node <Unit>_http_json_service_main_test___.js
# --smoke 模式
node <Unit>_http_json_service_main_test___.js --smoke
```

**调用侧**：

```bash
node <Unit>_http_json_call_main_test___.js
# 覆盖 Base URL
node <Unit>_http_json_call_main_test___.js http://10.0.0.5:8081/<Unit>
```

### 8.5 预期输出（调用侧）

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

### 8.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Cannot find module 'lingofuse-js'` | 未安装 | `npm install lingofuse-js` |
| `fetch is not defined` | Node < 18 | 升级 Node |
| `HTTPCallError` | 桥接程序未运行 | 启动桥接程序 |
| `ECONNREFUSED` | 桥接端口不对 | 检查 `--port` |

---

## 9. TypeScript

### 9.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service.ts` | TypeScript 服务 |
| `<Unit>_http_json_call_ts.ts` | TypeScript 调用模块 |
| `<Unit>_http_json_service_main_test___.ts` | 服务侧测试驱动 |
| `<Unit>_http_json_call_main_test___.ts` | 调用侧测试驱动 |
| `setup_ts_tests.ps1` | 环境准备脚本 |

### 9.2 前置依赖

- Node.js 18+。
- `lingofuse-ts`、`tsx`。

### 9.3 准备环境（推荐）

```powershell
.\setup_ts_tests.ps1 -TsLibDir D:\LingoFuse\ts\lingofuse-ts -RunSmoke
```

**手动**：

```bash
npm install lingofuse-ts tsx
```

### 9.4 运行测试

**服务侧**：

```bash
./node_modules/.bin/tsx.cmd <Unit>_http_json_service_main_test___.ts
# --smoke
./node_modules/.bin/tsx.cmd <Unit>_http_json_service_main_test___.ts --smoke
```

**调用侧**：

```bash
./node_modules/.bin/tsx.cmd <Unit>_http_json_call_main_test___.ts
# 覆盖 Base URL
./node_modules/.bin/tsx.cmd <Unit>_http_json_call_main_test___.ts http://10.0.0.5:8081/<Unit>
```

**Linux / macOS**：`./node_modules/.bin/tsx`

### 9.5 预期输出（调用侧）

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

### 9.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `tsx: not found` | 未安装 | `npm install tsx` |
| `Cannot find module 'lingofuse-ts'` | 未安装 | `npm install lingofuse-ts` |
| `TypeError: Cannot read property` | TS 编译目标不匹配 | 检查 `tsconfig.json` 的 `target` |
| `HTTPCallError` | 桥接程序未运行 | 启动桥接程序 |

---

## 10. PHP

### 10.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_call_php.php` | PHP 调用模块 |
| `<Unit>_http_json_call_main_test___.php` | 调用侧测试驱动 |

**PHP 无服务侧**（仅有调用侧）。

### 10.2 前置依赖

- PHP 7.4+。
- `curl` 扩展（首选）或 `allow_url_fopen=On`。

### 10.3 运行测试

```bash
php <Unit>_http_json_call_main_test___.php
# 覆盖 Base URL
php <Unit>_http_json_call_main_test___.php http://10.0.0.5:8081/<Unit>
```

### 10.4 预期输出（调用侧）

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator

  Add: OK
  Sub: OK

=== Summary ===
Passed: 2
Failed: 0
```

### 10.5 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Call to undefined function curl_init()` | 未装 curl 扩展 | `apt install php-curl` 或改 php.ini |
| `file_get_contents(): http:// wrapper is disabled` | `allow_url_fopen=Off` | 装 curl 扩展 |
| `HttpJsonCallError` | 桥接程序未运行 | 启动桥接程序 |
| `SSL certificate problem` | 桥接 https 证书 | 加 `--insecure` 或配置 CA |

---

## 11. Rust

### 11.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service_rs.rs` | Rust 服务 |
| `<Unit>_http_json_call_rs.rs` | Rust 调用模块 |
| `<Unit>_http_json_service_main_test___.rs` | 服务侧测试驱动 |
| `<Unit>_http_json_call_main_test___.rs` | 调用侧测试驱动 |

### 11.2 前置依赖

- Rust 1.70+。
- 调用侧 crate：`ureq`、`reqwest`、`tokio`、`serde_json`。
- 服务侧 crate：`lingofuse`、`serde_json`。

### 11.3 构建与运行（服务侧）

```bash
cargo new my_service
cd my_service
cargo add lingofuse --path ../LingoFuse/rust
cargo add serde_json
cp ../<Unit>_http_json_service_rs.rs src/
cp ../<Unit>_http_json_service_main_test___.rs src/main.rs
cargo run
```

### 11.4 构建与运行（调用侧）

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

### 11.5 预期输出（调用侧）

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

### 11.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `cargo: no such command: add` | cargo 版本过旧 | `rustup update` |
| `linking with cc failed` | 缺 C 链接器 | 装 MSVC Build Tools 或 gcc |
| `HttpCallError` | 桥接程序未运行 | 启动桥接程序 |
| `ureq::Error::Transport` | 网络错误 / 桥接未启动 | 检查桥接 |
| `tokio` runtime 报错 | `#[tokio::main]` 缺失 | 用生成代码里的 `#[tokio::main]` |

---

## 12. Go

### 12.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service_go.go` | Go 服务 |
| `<Unit>_http_json_call_go.go` | Go 调用模块 |
| `<Unit>_http_json_service_main_test.go` | 服务侧测试 |
| `<Unit>_http_json_call_main_test.go` | 调用侧测试 |

### 12.2 前置依赖

- Go 1.21+。
- 服务侧：`github.com/PassByYou888/LingoFuse/go`。
- 调用侧：仅标准库。

### 12.3 构建与运行（服务侧）

```bash
go mod init calculator
go get github.com/PassByYou888/LingoFuse/go
cp ../<Unit>_http_json_service_go.go .
cp ../<Unit>_http_json_service_main_test.go .
go test -v
# 或构建可执行文件
go build -o service .
./service
```

### 12.4 构建与运行（调用侧）

```bash
go mod init calculator_call
cp ../<Unit>_http_json_call_go.go .
cp ../<Unit>_http_json_call_main_test.go .
go test -v
```

### 12.5 预期输出（调用侧）

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

### 12.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `module github.com/PassByYou888/LingoFuse not found` | 未 `go get` | `go get github.com/PassByYou888/LingoFuse/go` |
| `undefined: HTTPCallError` | 调用模块未导入 | 确保 `_http_json_call_go.go` 与测试同包 |
| `cgo` 相关错误 | 服务侧需要 cgo | 设置 `CGO_ENABLED=1` |
| `HTTPCallError` | 桥接程序未运行 | 启动桥接程序 |

---

## 13. Java

### 13.1 产物

| 文件 | 说明 |
|------|------|
| `HttpJsonService.java` | Java 服务类 |
| `HttpJsonClient.java` | Java 调用类 |
| `HttpJsonServiceTest.java` | 服务侧测试驱动 |
| `HttpJsonCallTest.java` | 调用侧测试驱动 |

### 13.2 前置依赖

- JDK 11+（推荐 17+）。
- `jackson-databind.jar`。
- 服务侧：`lingofuse.jar`。

### 13.3 构建与运行（服务侧）

```bash
javac -cp lingofuse.jar:jackson-databind.jar *.java
java --enable-native-access=ALL-UNNAMED \
     -cp .:lingofuse.jar:jackson-databind.jar \
     HttpJsonService
# --smoke 模式
java --enable-native-access=ALL-UNNAMED \
     -cp .:lingofuse.jar:jackson-databind.jar \
     HttpJsonServiceTest --smoke
```

**Windows**：用 `;` 分隔 classpath：

```cmd
javac -cp lingofuse.jar;jackson-databind.jar *.java
java --enable-native-access=ALL-UNNAMED -cp .;lingofuse.jar;jackson-databind.jar HttpJsonService
```

### 13.4 构建与运行（调用侧）

```bash
javac -cp jackson-databind.jar HttpJsonClient.java HttpJsonCallTest.java
java -cp .:jackson-databind.jar HttpJsonCallTest
```

### 13.5 预期输出（调用侧）

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator

  Add: OK
  Sub: OK

=== Summary ===
Passed: 2
Failed: 0
```

### 13.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `ClassNotFoundException: com.fasterxml.jackson.databind.JsonNode` | Jackson 缺失 | 下载 `jackson-databind.jar` |
| `UnsatisfiedLinkError: LingoFuse64` | 原生库缺失 | 加到 `-Djava.library.path` |
| `ClassNotFoundException: lingofuse.AppHandle` | `lingofuse.jar` 缺失 | 装 LingoFuse Java 包 |
| `HTTPCallException` | 桥接程序未运行 | 启动桥接程序 |

---

## 14. Delphi

### 14.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_call_delphi.pas` | Delphi 调用单元 |
| `<Unit>_http_json_call_delphi_test___.dpr` | 调用侧测试驱动 |

**Delphi 无服务侧**（仅有调用侧）。

### 14.2 前置依赖

- Delphi 10.3+。
- 仅 RTL（`System.Net.HttpClient`、`System.JSON`、`System.Classes`）。

### 14.3 构建与运行

**方式 A：命令行**

```cmd
dcc32 <Unit>_http_json_call_delphi_test___.dpr
<Unit>_http_json_call_delphi_test___.exe
```

**方式 B：IDE**

1. 打开 `<Unit>_http_json_call_delphi_test___.dpr`。
2. `Build`。
3. `Run`。

### 14.4 预期输出（调用侧）

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

### 14.5 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Unit not found: System.Net.HttpClient` | Delphi < 10.3 | 升级 Delphi |
| `EHTTPCallError: Network error` | 桥接程序未运行 | 启动桥接程序 |
| 异步测试超时 | `CheckSynchronize` 未 pump | 生成代码已用 `PumpUntilSignaled`，无需处理 |

---

## 15. Dart

### 15.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service.dart` | Dart 服务 |
| `<Unit>_http_json_call.dart` | Dart 调用模块 |
| `<Unit>_http_json_service_main_test___.dart` | 服务侧测试 |
| `<Unit>_http_json_call_main_test___.dart` | 调用侧测试 |

### 15.2 前置依赖

`pubspec.yaml` 加：

```yaml
dependencies:
  http: ^1.0.0
```

服务侧还需要 `lingofuse` 包。

### 15.3 运行测试

**服务侧**：

```bash
dart run <Unit>_http_json_service_main_test___.dart
```

**调用侧**：

```bash
dart run <Unit>_http_json_call_main_test___.dart
# 覆盖 Base URL
dart run <Unit>_http_json_call_main_test___.dart http://10.0.0.5:8081/<Unit>
```

### 15.4 预期输出（调用侧）

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

### 15.5 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Error: Couldn't resolve the package 'http'` | 未 `dart pub get` | `dart pub get` |
| `HttpCallError` | 桥接程序未运行 | 启动桥接程序 |
| `LateInitializationError` | 服务未 init 完 | 等待 `visible` 日志 |

---

## 16. Swift

### 16.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service_swift.swift` | Swift 服务 |
| `<Unit>_http_json_call_swift.swift` | Swift 调用模块 |
| `<Unit>_http_json_service_main_test___.swift` | 服务侧测试 |
| `<Unit>_http_json_call_main_test___.swift` | 调用侧测试 |

### 16.2 前置依赖

- Swift 5.9+。
- macOS 12+ / iOS 15+（异步 API 需要）。

### 16.3 运行测试

**服务侧**：

```bash
swift <Unit>_http_json_service_main_test___.swift
```

**调用侧**：

```bash
swift <Unit>_http_json_call_main_test___.swift
```

### 16.4 预期输出（调用侧）

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

### 16.5 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `error: cannot find 'FoundationNetworking'` | Linux 需要显式导入 | 生成代码已处理 |
| `HTTPCallError` | 桥接程序未运行 | 启动桥接程序 |
| `@unchecked Sendable` 警告 | 正常并发标注 | 无需处理 |
| async pass 未运行 | macOS 12 以下 | 升级 OS，或用 sync pass |

---

## 17. Ruby

### 17.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service.rb` | Ruby 服务 |
| `<Unit>_http_json_call.rb` | Ruby 调用模块 |
| `<Unit>_http_json_service_main_test___.rb` | 服务侧测试 |
| `<Unit>_http_json_call_main_test___.rb` | 调用侧测试 |

### 17.2 前置依赖

- Ruby 2.7+ / 3.0+。
- 服务侧：`lingofuse` gem（C 扩展）。
- 调用侧：仅标准库。

### 17.3 运行测试

**服务侧**：

```bash
gem install lingofuse   # 仅需一次
ruby <Unit>_http_json_service_main_test___.rb
# --smoke 模式（进程内 LocalCall）
ruby <Unit>_http_json_service_main_test___.rb --smoke
```

**调用侧**：

```bash
ruby <Unit>_http_json_call_main_test___.rb
# 覆盖 Base URL
ruby <Unit>_http_json_call_main_test___.rb http://10.0.0.5:8081/<Unit>
```

### 17.4 预期输出（调用侧）

```
=== Calculator HTTP/JSON call test ===

Base URL: http://127.0.0.1:8081/Calculator

  Add [sync] : OK
  Sub [sync] : OK

=== Summary ===
Passed: 2
Failed: 0
```

### 17.5 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `cannot load such file -- lingofuse` | gem 未安装 | `gem install lingofuse` |
| `HTTPCallError` | 桥接程序未运行 | 启动桥接程序 |
| `dynamic constant assignment` | 误给 `HTTP_CALL_BASE_URL` 赋值 | 用 `Module.base_url = "..."` |
| 进程不退出 | `NativeBridge.start` 线程未 join | 生成代码已用 `exit!` 强制退出 |

---

## 18. Zig

### 18.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service_zig.zig` | Zig 服务 |
| `<Unit>_http_json_call_zig.zig` | Zig 调用模块 |
| `<Unit>_http_json_service_main_test___.zig` | 服务侧测试 |
| `<Unit>_http_json_call_main_test___.zig` | 调用侧测试 |
| `setup_zig_tests.ps1` | 环境准备脚本 |

### 18.2 前置依赖

- Zig 0.13+。
- `lingofuse` Zig 绑定。
- `LingoFuse64.dll` 与 `z_ipc_64.dll`。

### 18.3 准备环境（推荐）

```powershell
.\setup_zig_tests.ps1 -ZigLibDir D:\LingoFuse\zig -BinaryDir D:\LingoFuse\Binary
```

脚本会创建 `zig_service_test/` 与 `zig_call_test/` 两个工程。

### 18.4 运行测试

**服务侧**：

```bash
cd zig_service_test
zig build run
# 按 Enter 停止
```

**调用侧**：

```bash
cd zig_call_test
zig build run
# 按 Enter 退出
```

### 18.5 预期输出（调用侧）

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

### 18.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `zig build` 报 fingerprint mismatch | `build.zig.zon` 指纹过期 | 按报错信息替换 `.fingerprint` |
| `bridge app '__lf_http_bridge__' not found in mesh` | 桥接程序未启动 | 启动桥接程序 |
| `framework.init failed` | LingoFuse64.dll 不在 PATH | 复制 DLL 到 `zig_call_test/` |
| `std.array_list.Managed` 编译错误 | Zig 版本不符 | 用 Zig 0.13+ |

---

## 19. Erlang

### 19.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service.erl` | Erlang 服务模块 |
| `<Unit>_http_json_call.erl` | Erlang 调用模块 |
| `<Unit>_http_json_service_main_test___.escript` | 服务侧测试 |
| `<Unit>_http_json_call_main_test___.escript` | 调用侧测试 |
| `setup_erlang_tests.ps1` | 环境准备脚本 |

### 19.2 前置依赖

- Erlang/OTP 25+。
- `lingofuse` Erlang binding（含 `lingofuse_nif.dll`）。

### 19.3 准备环境（推荐）

```powershell
.\setup_erlang_tests.ps1 -ErlangBindingDir D:\LingoFuse\erlang -RunSmoke
```

### 19.4 运行测试

**服务侧**：

```bash
escript <Unit>_http_json_service_main_test___.escript
# --smoke 模式
escript <Unit>_http_json_service_main_test___.escript --smoke
```

**调用侧**：

```bash
escript <Unit>_http_json_call_main_test___.escript
# 覆盖 Base URL
escript <Unit>_http_json_call_main_test___.escript http://10.0.0.5:8081/<Unit>
```

### 19.5 预期输出（调用侧）

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

### 19.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `no such file or directory: lingofuse_nif.dll` | NIF 缺失 | `setup_erlang_tests.ps1` 会复制 |
| `{error, {http_error, econnrefused}}` | 桥接程序未运行 | 启动桥接程序 |
| `service_not_visible` | 服务未就绪（3 秒内） | 增大 `PROBE_RETRIES` |
| `undef` 报错 | 模块未编译 | `erlc -o ebin *.erl` |

---

## 20. Fortran

### 20.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service_mod.f90` | Fortran 服务模块 |
| `<Unit>_http_json_call_mod.f90` | Fortran 调用模块 |
| `<Unit>_http_json_service_main_test___.f90` | 服务侧测试 |
| `<Unit>_http_json_call_main_test___.f90` | 调用侧测试 |
| `setup_fortran_tests.ps1` | 环境准备脚本 |

### 20.2 前置依赖

- gfortran 9+ 或 ifort / flang。
- `lf_fortran_mod.f90` + `lf_fortran.cpp` + `LingoFuse.c`。
- `LingoFuse64.dll`。

### 20.3 准备环境（推荐）

```powershell
.\setup_fortran_tests.ps1 -FortranLibDir D:\LingoFuse\fortran\c_ext -RunSmoke
```

脚本会：

1. 编译 `lf_fortran_mod.f90`、`lf_fortran.cpp`、`LingoFuse.c`。
2. 编译 `<Unit>_http_json_service_mod.f90` 与 `<Unit>_http_json_call_mod.f90`。
3. 编译两个测试驱动。
4. 链接 `service_test.exe` 与 `call_test.exe`。

### 20.4 运行测试

**服务侧**：

```bash
cd _build_fortran
./service_test.exe
# --smoke 模式
./service_test.exe --smoke
```

**调用侧**：

```bash
cd _build_fortran
./call_test.exe
# 覆盖 Base URL
./call_test.exe http://10.0.0.5:8081/<Unit>
```

### 20.5 预期输出（调用侧）

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

### 20.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `gfortran: command not found` | 未装 | `apt install gfortran` 或 MinGW-w64 |
| `undefined reference to 'lf_*'` | `lf_fortran.cpp` 未链接 | 用 `setup_fortran_tests.ps1` |
| `c_funloc ... not a variable` | 空参数列表写法 | 生成代码已修（v4） |
| `HTTPCallError` | 桥接程序未运行 | 启动桥接程序 |

---

## 21. Julia

### 21.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service.jl` | Julia 服务模块 |
| `<Unit>_http_json_call.jl` | Julia 调用模块 |
| `<Unit>_http_json_service_main_test___.jl` | 服务侧测试 |
| `<Unit>_http_json_call_main_test___.jl` | 调用侧测试 |
| `setup_julia_tests.ps1` | 环境准备脚本 |

### 21.2 前置依赖

- Julia 1.9+（推荐 1.10+）。
- **必须 `--threads=2` 或更多**（LingoFuse 回调消费需要）。
- `LingoFuse`、`JSON3` 包。

### 21.3 准备环境（推荐）

```powershell
.\setup_julia_tests.ps1 -JuliaBindingDir D:\LingoFuse\julia -RunSmoke
```

### 21.4 运行测试

**服务侧**：

```bash
julia --project=<GenDir> --threads=2 <Unit>_http_json_service_main_test___.jl
# --smoke 模式
julia --project=<GenDir> --threads=2 <Unit>_http_json_service_main_test___.jl --smoke
```

**调用侧**：

```bash
julia --project=<GenDir> --threads=2 <Unit>_http_json_call_main_test___.jl
# 覆盖 Base URL / Endpoint
julia --project=<GenDir> --threads=2 <Unit>_http_json_call_main_test___.jl \
    http://10.0.0.5:8081/<Unit> ipc:Calculator_http_json
```

### 21.5 预期输出（调用侧）

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

### 21.6 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `FATAL: --threads=2 or more required` | 单线程 | 加 `--threads=2` |
| `ArgumentError: Package LingoFuse not found` | 未装 | `setup_julia_tests.ps1` |
| `HTTPCallError` | 桥接程序未运行 | 启动桥接程序 |
| `prepare_client returned -1` | 端点已被占用 | 检查端口，或换端点 |

---

## 22. R

### 22.1 产物

| 文件 | 说明 |
|------|------|
| `<Unit>_http_json_service.R` | R 服务 |
| `<Unit>_http_json_service_impl.R` | R 用户实现桩 |
| `<Unit>_http_json_call.R` | R 调用模块 |
| `<Unit>_http_json_service_main_test___.R` | 服务侧测试 |
| `<Unit>_http_json_call_main_test___.R` | 调用侧测试 |
| `setup_r_tests.ps1` | 环境准备脚本 |

### 22.2 前置依赖

- R 4.0+。
- `lingofuse`、`jsonlite`、`httr`、`future` 四个包。

### 22.3 准备环境（推荐）

```powershell
.\setup_r_tests.ps1 -RLibDir D:\LingoFuse\r\lingofuse -InstallMissing -RunSmoke
```

### 22.4 运行测试

**服务侧**：

```bash
# 先设置环境变量
export LINGOFUSE_RUNTIME=/path/to/LingoFuse64
Rscript <Unit>_http_json_service_main_test___.R
```

**调用侧**：

```bash
export LINGOFUSE_RUNTIME=/path/to/LingoFuse64
Rscript <Unit>_http_json_call_main_test___.R
```

### 22.5 停止 R 服务

R 服务监听 `service.exit` 哨兵文件。**打开第二个 PowerShell 窗口**：

```powershell
'' > "<脚本目录>\service.exit"
```

服务会在约 100ms 内检测到，按顺序执行 `exit_main_thread` → `free_app` → `shutdown`，然后退出。

**Ctrl+C 是备选方案**，但某些平台可能留下终端状态异常。

### 22.6 预期输出（调用侧）

```
=== Calculator HTTP/JSON call test ===
Base URL: http://127.0.0.1:8081/Calculator

  Add: OK
  Sub: OK

=== Summary ===
Passed: 2
Failed: 0
```

### 22.7 常见问题

| 症状 | 原因 | 修复 |
|------|------|------|
| `Package 'lingofuse' is required` | 未装 | `setup_r_tests.ps1 -InstallMissing` |
| `Cannot locate the LingoFuse runtime` | 未设 `LINGOFUSE_RUNTIME` | 设环境变量 |
| `The *_async variants require future::plan('sequential')` | future 计划不兼容 | `future::plan(future::sequential)` |
| `HTTPCallError` | 桥接程序未运行 | 启动桥接程序 |

---

## 23. 通用故障排查

### 23.1 症状 → 原因 → 修复

| 症状 | 最可能的原因 | 修复 |
|------|--------------|------|
| 所有语言都报 `Network error` / `Connection refused` | **桥接程序未运行** | 启动 `bridge.py` |
| 桥接程序终端没有任何日志 | 桥接程序启动失败 | 检查 `--endpoint` 参数与 `bridge.py` 路径 |
| `LF_PrepareClient returned -1` | 端点已被其他进程占用 | 换端点，或杀旧进程 |
| `LF_PrepareDone returned 0` | 同一进程已调用过 | 重启进程 |
| `no found app("<name>")` | 目标 App 不在 mesh 上 | 服务侧未启动，或端点不一致 |
| `code=-3`（`-3 bridge precheck`） | 桥接程序预检查缓存未更新 | 桥接加 `--no-precheck` |
| `code=-4`（协议错误） | 桥接响应畸形 | 检查桥接版本与服务版本 |
| 服务侧报 `Address already in use` | 端点已被占用 | 换端点，或杀旧进程 |
| 服务侧跑起来但调用侧拿不到响应 | 端点字符串不一致 | 两侧都用 `ipc:<Unit>_http_json` |
| 调用侧超时 | 服务侧阻塞 / 桥接阻塞 | 看服务侧日志 |
| 调用侧报 `int64` 精度问题 | JS `Number` 精度限制 | 服务侧返回字符串 |
| 桥接程序被误关 | 误关终端 | 重启桥接程序；调用侧不必重启 |

### 23.2 三进程的"健康检查"顺序

1. **服务侧**：看它有没有打印 `[OK] Service ready` 或类似日志。
2. **桥接程序**：看它有没有打印 HTTP 监听日志（`Listening on 127.0.0.1:8081` 或类似）。
3. **调用侧**：跑测试驱动。

**任何一步失败，先修复那一步再继续。**

### 23.3 端点字符串的常见错误

| 错误写法 | 正确写法 |
|----------|----------|
| `Calculator` | `ipc:Calculator_http_json` |
| `ipc:calculator_http_json`（大小写） | `ipc:Calculator_http_json`（与 `<UnitName>` 完全一致） |
| `ipc:Calculator` | `ipc:Calculator_http_json` |
| `tcp://127.0.0.1:8081/Calculator` | `ipc:Calculator_http_json` |

**端点字符串必须两侧完全一致**。桥接程序的 `--endpoint` 与服务侧的 `HTTP_SERVICE_ENDPOINT` / `ENDPOINT` 常量必须相同。

### 23.4 测试驱动的退出码

| 退出码 | 含义 |
|:------:|------|
| `0` | 全部通过 |
| `1` | 有失败，或超时，或启动失败 |

**CI 里依赖退出码，不要解析 stdout 文字。**

### 23.5 日志级别

| 语言 | 开启 debug 日志的方式 |
|------|----------------------|
| Pascal | 设置 `DEBUG_LOG = True`（在服务代码里） |
| Python | 设置 `DEBUG_LOG = True`（`<Unit>_http_json_call.py` 顶部） |
| C++ | 设置 `DEBUG_LOG = true`（在服务 / 调用代码里） |
| C# | 设置 `AppInfo.DebugLog = true` 或 `HttpJsonCallConfig.DebugLog = true` |
| JS | `DEBUG_LOG = true`（在 `<Unit>_http_json_call.js` 里） |
| Node.js | `process.env.LINGOFUSE_DEBUG = '1'` 或 `DEBUG_LOG = true` |
| TypeScript | `HttpJsonCallConfig.debugLog = true` |
| PHP | `HttpJsonCallConfig::$debugLog = true` |
| Rust | `set_debug_log(true)` |
| Go | `SetDebugLog(true)` |
| Java | `-DLINGOFUSE_DEBUG=1` 或环境变量 |
| Dart | `DEBUG_LOG = true` |
| Swift | `baseUrl` 前设 `debugLog = true` |
| Ruby | `Module.debug_log = true` |
| Zig | `call.DEBUG_LOG = true` |
| Erlang | `DEBUG_LOG` 常量（在生成模块里） |
| Fortran | `DEBUG_LOG = .true.` |
| Julia | `DEBUG_LOG = true`（模块常量） |
| R | `DEBUG_LOG` 常量（在生成模块里） |

**开启 debug 后，每次请求与响应都会打到 stderr，便于定位问题。**

### 23.6 各语言测试驱动的同步 / 异步覆盖

| 语言 | 同步 | 异步 | 备注 |
|------|:----:|:----:|------|
| Pascal | ✅ | ✅ | `_P` 变体不测试（nested 限制） |
| Python | ✅ | ✅ | `await` 变体 |
| C++ | ✅ | ✅ | `std::promise` + `std::future` |
| C# | ✅ | ✅ | `TaskCompletionSource` |
| JavaScript | — | ✅ | 仅 `await` / `Promise` |
| Node.js | — | ✅ | 仅 `await` / `Promise` |
| TypeScript | — | ✅ | 仅 `await` / `Promise` |
| PHP | ✅ | — | 仅同步 |
| Rust | ✅ | ✅ | `ureq` / `reqwest` |
| Go | ✅ | ✅ | 同步 / channel |
| Java | ✅ | — | 仅同步（HTTP 客户端） |
| Delphi | ✅ | ✅ | `TThread` 子类 |
| Dart | — | ✅ | 仅 `Future` |
| Swift | ✅ | ✅ | `DispatchSemaphore` / `async` |
| Ruby | ✅ | — | 仅同步（可 `Thread.new` 并发） |
| Zig | ✅ | ✅ | LingoFuse `callAsync` |
| Erlang | ✅ | ✅ | `spawn` |
| Fortran | ✅ | ✅ | `lf_async_call` |
| Julia | ✅ | ✅ | `Task` / `future` |
| R | ✅ | ✅ | 同步 / `future` |

---

## 附录：一页速查表

| 语言 | 服务测试命令 | 调用测试命令 | 需要桥接？ |
|------|-------------|-------------|:----------:|
| Pascal | `./<U>_http_json_service_main_test___ [--smoke]` | `./<U>_http_json_call_main_test___ [<base_url>]` | ✅ |
| Python | `python3 <U>_http_json_service_main_test___.py [--smoke]` | `python3 <U>_http_json_call_main_test___.py [<base_url>]` | ✅ |
| C++ | `./<U>_http_json_service` | `./<U>_http_json_call_test` | ✅ |
| C# | `dotnet run [-- --smoke]` | `dotnet run` | ✅ |
| JavaScript | 双击 `*_test.html` | 双击 `*_test.html` | ✅ |
| Node.js | `node <U>_http_json_service_main_test___.js [--smoke]` | `node <U>_http_json_call_main_test___.js [<base_url>]` | ✅ |
| TypeScript | `tsx <U>_http_json_service_main_test___.ts [--smoke]` | `tsx <U>_http_json_call_main_test___.ts [<base_url>]` | ✅ |
| PHP | — | `php <U>_http_json_call_main_test___.php [<base_url>]` | ✅ |
| Rust | `cargo run`（src/main.rs 指向 service test） | `cargo run`（src/main.rs 指向 call test） | ✅ |
| Go | `go test -v`（service test 目录） | `go test -v`（call test 目录） | ✅ |
| Java | `java HttpJsonServiceTest [--smoke]` | `java HttpJsonCallTest [<base_url>]` | ✅ |
| Delphi | — | `dcc32 <U>_http_json_call_delphi_test___.dpr` 后运行 `.exe` | ✅ |
| Dart | `dart run <U>_http_json_service_main_test___.dart` | `dart run <U>_http_json_call_main_test___.dart [<base_url>]` | ✅ |
| Swift | `swift <U>_http_json_service_main_test___.swift` | `swift <U>_http_json_call_main_test___.swift` | ✅ |
| Ruby | `ruby <U>_http_json_service_main_test___.rb [--smoke]` | `ruby <U>_http_json_call_main_test___.rb [<base_url>]` | ✅ |
| Zig | `cd zig_service_test && zig build run` | `cd zig_call_test && zig build run` | ✅ |
| Erlang | `escript <U>_http_json_service_main_test___.escript [--smoke]` | `escript <U>_http_json_call_main_test___.escript [<base_url>]` | ✅ |
| Fortran | `./service_test.exe [--smoke]` | `./call_test.exe [<base_url>]` | ✅ |
| Julia | `julia --threads=2 <U>_http_json_service_main_test___.jl [--smoke]` | `julia --threads=2 <U>_http_json_call_main_test___.jl [<base_url>] [<endpoint>]` | ✅ |
| R | `Rscript <U>_http_json_service_main_test___.R` | `Rscript <U>_http_json_call_main_test___.R` | ✅ |

**`<U>` = 规范化后的单元名；`<base_url>` 默认为 `http://127.0.0.1:8081/<U>`；`<endpoint>` 默认为 `ipc:<U>_http_json`。**

**桥接程序必须始终运行——这句话在所有语言里都是同一件事。**
