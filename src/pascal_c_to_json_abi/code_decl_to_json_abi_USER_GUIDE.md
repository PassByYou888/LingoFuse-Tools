# code_decl_to_json_abi 用户指南（v3·中文扩展版，无 Markdown 产物）

> **文档定位** — 本文档是 `code_decl_to_json_abi` 工具链的**面向用户的操作手册**。它覆盖：GUI、CLI、MCP 三前端操作，程序化接口，全部目标语言的支持矩阵与产物清单，桥接程序的全局前提，接口契约的获取方式，构建与部署实战，常见问题与故障排查。
>
> **本版的重大变化（相对英文原版 v3）** — 新版本**不再生成 `_readme.md` 伴随文档**。`.md` 生成功能已从工具链中移除。取而代之的是：
>
> - **生成代码顶部的注释块**承载接口说明；
> - **桩函数签名**（`internal_call_<Api>`）本身就是最权威的接口契约；
> - **`CMakeLists.txt` 与 `test_main___.cpp`** 承载 C++ 侧的构建与调用契约；
> - **`launch_bridge.ps1` 与 `setup_*_tests.ps1`** 承载桥接与测试环境的准备契约；
> - **各语言的测试驱动**（`*_main_test___.*`）本身就是最权威的调用示例。
>
> 因此本版**第 3 章**从英文原版的"读 `.md`"改为"**接口契约从哪里读**"，并新增了完整的"**构建与部署实战**"章节（第 14 章）以补偿 `.md` 移除后丢失的信息密度。
>
> **运行期最重要的一条规则** — **桥接程序（`bridge.py` / `bridge.exe`）必须始终运行**。每一个生成的调用侧产物最终都依赖它。见第 2 章。
>
> **生成后最重要的一条规则** — **从代码本身、CMake 脚本、测试驱动、桩签名读契约**。`internal_call_<Api>` 的签名就是接口的最终定义；`CMakeLists.txt` 的 target 名就是构建的最终定义；`test_main___.cpp` 就是调用方式的最权威示例。见第 3 章。
>
> **v3 的 MCP 变化** — MCP API 已从 24 个工具缩减为**恰好三个工具**：
>
> - `CodeDeclToJsonAbi_Generate(Source, Language)`
> - `CodeDeclToJsonAbi_ListFiles()`
> - `CodeDeclToJsonAbi_GetFile(FileName)`
>
> 一次 `Generate` 调用现在会一次性产出**所有目标语言**的代码，外加 CMake 构建脚本与 C++ 测试驱动。
>
> **本中文扩展版的额外内容** — 在英文原版 v3 的基础上：完整的语言支持矩阵（覆盖 `.lpr` 中注册的全部 20+ 目标语言）、每种目标语言的产物清单与示例文件名、每个生成器单元的行为说明、桥接程序生命周期与三种进程布局的详细说明、更多故障排查条目、更完整的 MCP 工具调用示例、程序化接口的最小可行嵌入与完整嵌入示例、错误码与异常类型速查表、术语表、**构建与部署实战**、**典型工作流完整走查**、**接口契约获取入口对照表**。本版规模**显著大于**英文原版。

---

## 目录

### 第一部分 — 项目总览

- [第 1 章　项目概述](#第-1-章项目概述)
- [第 2 章　全局前提：桥接程序必须始终运行](#第-2-章全局前提桥接程序必须始终运行)
- [第 3 章　接口契约从哪里读](#第-3-章接口契约从哪里读)

### 第二部分 — 环境与准备

- [第 4 章　环境准备](#第-4-章环境准备)

### 第三部分 — 三种前端操作

- [第 5 章　GUI 操作指南](#第-5-章gui-操作指南)
- [第 6 章　命令行操作指南](#第-6-章命令行操作指南)
- [第 7 章　智能体（MCP-API）操作指南——三个工具](#第-7-章智能体mcp-api操作指南三个工具)

### 第四部分 — MCP 工具提供器架构

- [第 8 章　MCP 工具提供器单元是如何构建的](#第-8-章mcp-工具提供器单元是如何构建的)

### 第五部分 — 程序化接口

- [第 9 章　程序化接口](#第-9-章程序化接口)

### 第六部分 — 产物、协议与安全

- [第 10 章　产物清单](#第-10-章产物清单)
- [第 11 章　JSON 安全与稳定性](#第-11-章json-安全与稳定性)

### 第七部分 — 语言支持与扩展

- [第 12 章　语言支持：今天与明天](#第-12-章语言支持今天与明天)

### 第八部分 — 常见问题与故障排查

- [第 13 章　常见问题解答](#第-13-章常见问题解答)

### 第九部分 — 构建与部署实战

- [第 14 章　构建与部署实战](#第-14-章构建与部署实战)
- [第 15 章　典型工作流完整走查](#第-15-章典型工作流完整走查)

### 附录

- [附录 A — 一次运行的产物清单](#附录-a一次运行的产物清单)
- [附录 B — 错误码与异常类型速查表](#附录-b错误码与异常类型速查表)
- [附录 C — 命令行参数速查表](#附录-c命令行参数速查表)
- [附录 D — MCP 工具参数速查表](#附录-dmcp-工具参数速查表)
- [附录 E — 语言支持矩阵](#附录-e语言支持矩阵)
- [附录 F — 接口契约获取入口对照表](#附录-f接口契约获取入口对照表)
- [附录 G — 各目标语言的产物文件后缀速查](#附录-g各目标语言的产物文件后缀速查)
- [附录 H — 术语表](#附录-h术语表)

---

## 第 1 章　项目概述

### 1.1 这个工具是什么

`code_decl_to_json_abi` 是一个**跨语言代码生成器**。

你给它一份 Pascal 单元（`.pas` / `.pp` / `.p`）或一份 C 头文件（`.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx`），它会：

1. **解析**出文件里所有顶层函数/过程声明；
2. **规范化**为一份中间模型（LV1 Model）；
3. **生成**一整套**HTTP POST + JSON** 接口代码，覆盖：
   - **服务侧**（Service）：把函数注册为 LingoFuse Call API，接收 JSON 请求并返回 JSON 响应；
   - **调用侧**（Call）：把本地函数调用转换为到桥接程序的 HTTP POST；
   - **测试程序**：服务侧自测程序 + 调用侧端到端测试程序；
   - **构建脚本**：针对 C++ 目标的 CMake 脚本 + C++ 测试驱动；
   - **环境准备脚本**：桥接启动脚本 + 各语言的测试环境准备脚本。

**一句话总结**：你写一份 Pascal 单元或 C 头文件，这个工具为你铺开所有跨语言、跨进程的 HTTP/JSON 接口——包括 C++ 侧的 CMake 构建脚本与各语言的完整测试套件。

### 1.2 支持哪些源语言

**仅两种**：

| 源语言 | 文件扩展名 |
|--------|-----------|
| Pascal | `.pas` / `.pp` / `.p` |
| C | `.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx` |

**关键区分**：

- **源语言（Source Language）** = 你输入的语言 = `pascal` 或 `c`。
- **目标语言（Target Language）** = 生成产物的语言 = 下面 §1.3 的任意一种。

**这是新手最常犯的错误**：把目标语言（`python`、`cpp`、`csharp`、`javascript`）当作源语言传入 MCP 工具，会立刻被拒绝。

### 1.3 支持哪些目标语言

本工具链实际注册的目标语言（依据 `.lpr` 文件中的 `uses` 列表）覆盖以下 20+ 种：

| # | 目标语言 | 服务侧 | 调用侧 | 测试程序 | 构建脚本 | 备注 |
|:-:|----------|:------:|:------:|:--------:|:--------:|------|
| 1 | **Pascal** | ✅ | ✅ | ✅ | — | 原生 FPC / Delphi 支持 |
| 2 | **Python** | ✅ | ✅ | ✅ | — | `requests` 依赖 |
| 3 | **C++** | ✅ | ✅ | ✅ | ✅ | CMake + 测试驱动 |
| 4 | **C#** | ✅ | ✅ | ✅ | — | .NET 8+ |
| 5 | **JavaScript**（浏览器） | ❌ | ✅ | ✅（HTML） | — | 自包含 HTML 测试页 |
| 6 | **Node.js** | ✅ | ✅ | ✅ | ✅ | 需要 `lingofuse-js` |
| 7 | **TypeScript** | ✅ | ✅ | ✅ | ✅ | 需要 `lingofuse-ts` + `tsx` |
| 8 | **PHP** | ❌ | ✅ | ✅ | — | 纯 `curl` / `fopen` |
| 9 | **Rust** | ✅ | ✅ | ✅ | — | `ureq` + `reqwest` + `tokio` |
| 10 | **Go** | ✅ | ✅ | ✅ | — | 标准库 |
| 11 | **Java** | ✅ | ✅ | ✅ | — | JDK 11+ + Jackson |
| 12 | **Delphi** | ❌ | ✅ | ✅ | — | 原生 RTL |
| 13 | **Dart** | ✅ | ✅ | ✅ | — | `http` 包 |
| 14 | **Swift** | ✅ | ✅ | ✅ | — | Foundation + `Dispatch` |
| 15 | **Ruby** | ✅ | ✅ | ✅ | — | `lingofuse` gem |
| 16 | **Zig** | ✅ | ✅ | ✅ | ✅ | `std` 标准库 |
| 17 | **Erlang** | ✅ | ✅ | ✅ | ✅ | `httpc` 标准库 |
| 18 | **Fortran** | ✅ | ✅ | ✅ | ✅ | `iso_c_binding` |
| 19 | **Julia** | ✅ | ✅ | ✅ | ✅ | `LingoFuse` + `JSON3` |
| 20 | **R** | ✅ | ✅ | ✅ | ✅ | `lingofuse` + `jsonlite` + `httr` + `future` |
| 21 | **Bridge 启动脚本** | — | — | — | ✅ | `launch_bridge.ps1` |

> **重要提示**：每种目标语言的完整构建命令、依赖、环境变量、故障排查表**不再由生成的 `.md` 承载**（新版本已移除 `.md` 生成）。取而代之：
>
> - **接口契约**从桩签名与生成代码顶部注释块读（见第 3 章）。
> - **构建命令**从 CMake 脚本、`setup_*_tests.ps1`、本文档第 14 章读。
> - **调用示例**从各语言的测试驱动（`*_main_test___.*`）读。
> - **故障排查**见本文档第 13 章与第 14 章。

### 1.4 产物数量

**数量随模型中的支持函数数量与目标语言的覆盖范围而变化**。以五语言口径（Pascal / Python / C++ / C# / JavaScript）为例：

| 序号 | 产物 |
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

**共 20 份**（英文原版 v3 里因为包含 README 而报"26 份"，其中 7 份是 README；现在 README 移除，剩 19–20 份纯产物，具体数字取决于是否把 `test_main___.cpp` 与 `CMakeLists.txt` 分别计）。

如果模型触发了更多目标语言（例如同时启用 Rust、Go、Java），产物数量会相应增加，可达 60+ 份。**每次运行的真实产物清单以 MCP 的 `Generate` 返回值或 GUI 的 "Final Source" 列表为准。**

### 1.5 三个前端

三者共享**同一个 GUI 表单**，不存在并行实现：

| 前端 | 触发条件 | 目标用户 |
|------|----------|----------|
| **GUI** | 无参数启动 | 人类工程师 |
| **CLI** | 带 ≥1 个参数启动 | 构建脚本、CI |
| **MCP** | GUI 启动后自动运行 | 智能体、远程工具 |

### 1.6 三个 MCP 工具

| # | 工具 | 用途 |
|:-:|------|------|
| 1 | `CodeDeclToJsonAbi_Generate(Source, Language)` | 解析 + 生成全部产物，返回文件清单 |
| 2 | `CodeDeclToJsonAbi_ListFiles()` | 返回产物文件名列表 |
| 3 | `CodeDeclToJsonAbi_GetFile(FileName)` | 按名字返回单个文件的完整内容 |

### 1.7 两步工作流

```
第 1 步：Generate(Source, "pascal" | "c")  → {"status":"ok","count":20,"files":[...]}
第 2 步：ListFiles()                        → {"status":"ok","count":20,"files":[...]}
        GetFile("CMakeLists.txt")           → {"status":"ok","name":"...","text":"..."}
```

**没有第 3 步**。没有中间检查工具。**没有 README 产物**。

### 1.8 八条必须记住的规则

1. **`Language` 只接受 `"pascal"` 或 `"c"`**。`"python"`、`"cpp"`、`"csharp"`、`"javascript"` 是**目标**语言，不是源语言。传错立刻报错。
2. **`Generate` 一次产出所有目标**。没有"按目标逐个调用"的接口。想要 Python 服务，`Generate` 后从清单里按名字 `GetFile` 即可。
3. **`ListFiles` 和 `GetFile` 是纯读取**。它们不会重跑任何生成器。要刷新，重新调用 `Generate`。
4. **一次 `Generate` 对应一份源文本**。重复调用会替换整个会话。
5. **服务侧与调用侧必须来自同一份源文本**。
6. **三种 ABI 家族之外的类型会导致整个函数被静默丢弃**（见 §4.3）。
7. **`int64` / `uint64` 在 JavaScript 客户端会丢精度**，因为 JS `Number` 是 IEEE-754 double（见 §11.5）。
8. **任何生成的调用侧产物都要求桥接程序正在运行**（见第 2 章）。

### 1.9 接口契约在哪里（新版本的核心变化）

英文原版 v3 的"读 `.md`"规则已被新版本取消。**新版本没有 `.md`**。接口契约必须从以下实体读取：

| 契约类型 | 权威来源 |
|----------|----------|
| **API 名** | `<U>_http_json_service_*` 里的注册表（`LF_RegisterCallEx(...)` 的第一个参数） |
| **参数类型与个数** | `internal_call_<Api>` 桩函数的签名 |
| **返回类型** | `internal_call_<Api>` 桩函数的返回声明 |
| **线上请求形状** | `{ "args": [v1, v2, ...] }`（固定，见第 10 章） |
| **线上响应形状** | `{ "code": 0, "result": ... }` / `{ "code": -1, "error": ... }`（固定，见第 10 章） |
| **调用示例** | 各语言的 `*_main_test___.*` 测试驱动 |
| **构建命令** | C++：`CMakeLists.txt` 的目标名；Python：`python` 直接运行；其他：见第 14 章 |
| **环境变量** | 生成代码顶部的注释块 |
| **服务端点名** | `HTTP_SERVICE_ENDPOINT` / `ENDPOINT` 常量（各语言语法不同，见第 10 章） |
| **桥接程序名** | `__lf_http_bridge__` / `__lf_outbound_post__`（各语言默认值一致） |

**第 3 章会把这九类契约逐条展开**。

### 1.10 本文档的阅读顺序建议

| 你的身份 | 建议阅读顺序 |
|----------|--------------|
| **第一次使用** | 第 1 章 → 第 2 章 → 第 3 章 → 第 4 章 → 第 5 章（GUI）→ 第 14 章（构建与部署） |
| **CI / 构建工程师** | 第 1 章 → 第 2 章 → 第 6 章（CLI）→ 第 14 章 |
| **智能体开发者** | 第 1 章 → 第 7 章（MCP）→ 第 8 章（架构） |
| **想嵌入生成器** | 第 1 章 → 第 9 章（程序化接口） |
| **运维 / 部署** | 第 2 章 → 第 10 章（产物清单）→ 第 14 章 → 第 13 章（FAQ） |

---

## 第 2 章　全局前提：桥接程序必须始终运行

> **这是运行期最重要的前提。在读其他任何章节之前，先读这一章。**

### 2.1 桥接程序是什么

**`bridge.py`（或编译后的 `bridge.exe`）是 LingoFuse 提供的 HTTP↔RPC 转发工具。**

它唯一的职责是：**把 HTTP 请求翻译成 LingoFuse 内部调用，再把返回值翻译成 HTTP 响应。**

```
HTTP 客户端  ──HTTP POST──▶  bridge.py / bridge.exe  ──LF_Call──▶  服务
HTTP 客户端  ◀─HTTP 响应──   bridge.py / bridge.exe  ◀─LF 返回───  服务
```

### 2.2 为什么它必须始终运行

**本工具生成的每一个调用侧产物**（Pascal / Python / C++ / C# / JavaScript / Node.js / TypeScript / PHP / Rust / Go / Java / Delphi / Dart / Swift / Ruby / Zig / Erlang / Fortran / Julia / R）以及**随附的 HTML 测试页**都**不直接**与服务通信。它们全部经由桥接程序：

| 调用侧产物 | 通信方式 |
|-----------|----------|
| Pascal 调用侧 | 内部使用 `LFHttpPost` 经 LingoFuse 到达桥接程序 |
| Python 调用侧 | 用 `requests.post(...)` 直接向桥接程序的 HTTP 端口发送请求 |
| C++ 调用侧 | 经 LingoFuse C ABI 到达桥接程序 |
| C# 调用侧 | 经 LingoFuse .NET 绑定到达桥接程序 |
| JavaScript 调用侧 | 用 `fetch(...)` 直接向桥接程序的 HTTP 端口发送 POST |
| Node.js 调用侧 | 用 `fetch(...)`（Node 18+）直接向桥接程序发送 POST |
| TypeScript 调用侧 | 同 Node.js |
| PHP 调用侧 | 用 `curl_*` 或 `fopen` + `stream_get_meta_data` |
| Rust 调用侧 | 同步用 `ureq`，异步用 `reqwest` + `tokio` |
| Go 调用侧 | 用 `net/http` 标准库 |
| Java 调用侧 | 用 `java.net.http.HttpClient` |
| Delphi 调用侧 | 用 `System.Net.HttpClient` |
| Dart 调用侧 | 用 `package:http` |
| Swift 调用侧 | 用 `URLSession` |
| Ruby 调用侧 | 用 `net/http` 标准库 |
| Zig 调用侧 | 经 LingoFuse 到达桥接程序 |
| Erlang 调用侧 | 用 `httpc` 标准库 |
| Fortran 调用侧 | 经 LingoFuse C ABI |
| Julia 调用侧 | 经 LingoFuse `future` / `call` |
| R 调用侧 | 经 LingoFuse `lf_call` |
| **HTML 测试页** | 同 JavaScript 调用侧 |
| **C++ 测试驱动**（`test_main___.cpp`） | 同 C++ 调用侧 |

**只要桥接程序不在运行，上面所有调用侧与测试页都会立刻失败。** 典型症状：

- `EHTTPCallError: ... Network error`（Pascal）
- `HTTPCallError: Network error`（Python）
- `HTTPCallError: ... (code=-1, http_status=0)`（C++ / C# / Java）
- `Failed to fetch` / CORS 错误（JS / 浏览器）
- `Connection refused`（手动 `curl` 测试）
- `ureq::Error::Transport` / `reqwest::Error`（Rust）
- `Net::OpenTimeout` / `Net::ReadTimeout`（Ruby）
- `TimeoutError` / `ConnectionError`（Python `requests`）

### 2.3 桥接程序的生命周期规则

| 规则 | 说明 |
|------|------|
| **必须单独启动** | 桥接程序是独立进程。它与你的调用侧、服务侧**分开**运行。 |
| **必须常驻** | 只要你打算调用接口或运行测试页，桥接程序**必须保持运行**。 |
| **不要与调用侧/服务侧挤在同一个终端** | 在**独立终端**里启动桥接程序。 |
| **必须早于调用侧就绪** | 推荐的启动顺序：**服务 → 桥接程序 → 调用侧**。 |
| **重启即可恢复** | 桥接程序崩溃或被杀死后，重新运行即可；调用侧不必重启。 |
| **不需要重启时不要重启** | 桥接程序支持 `Overlap_Connection`，重启不会影响已经就绪的服务。 |

### 2.4 推荐的三进程布局

```
终端 1（服务侧）：  启动生成的服务（Pascal / Python / C++ / C# / Rust / ...）
终端 2（桥接）：    python3 bridge.py --endpoint <与服务相同的 endpoint> --port 8081 --no-precheck
终端 3（调用侧）：  启动生成的调用侧，或双击 HTML 测试页
```

**桥接程序必须在终端 2 前台常驻。** 只有在你看到它打印出 HTTP 监听日志之后，才可以开始调用。

### 2.5 三种进程之间的依赖关系

```
         ┌─────────────────┐
         │  服务进程        │  ← 必须在线
         │  (Service)      │
         └────────┬────────┘
                  │ LF_Call
                  ▼
         ┌─────────────────┐
         │  桥接程序进程    │  ← 必须在线，前台常驻
         │  (bridge.py)    │
         └────────┬────────┘
                  │ HTTP POST
                  ▼
         ┌─────────────────┐
         │  调用侧进程      │  ← 按需启动
         │  (Call)         │
         └─────────────────┘
```

**三者缺一不可**：

- **只有服务、没有桥接** → 调用侧报 `Network error`。
- **只有桥接、没有服务** → 桥接程序报 API 不可用 / 超时。
- **三者都在但启动顺序不对** → 按 "服务 → 桥接 → 调用" 重启。

### 2.6 桥接程序不需要参与的阶段

**以下阶段不需要桥接程序**：

| 阶段 | 是否需要桥接程序 |
|------|:----------------:|
| GUI 中生成代码 | ❌ 不需要 |
| CLI 生成代码 | ❌ 不需要 |
| MCP 调用 `Generate` / `ListFiles` / `GetFile` | ❌ 不需要 |
| 从代码 / CMake / 测试驱动读取接口契约 | ❌ 不需要 |
| 编译生成的服务侧代码 | ❌ 不需要 |
| 编译生成的调用侧代码 | ❌ 不需要 |
| **运行**生成的服务侧代码 | ❌ 不需要 |
| **运行**生成的调用侧代码 | ✅ **必须** |
| **打开** HTML 测试页 | ✅ **必须** |
| **运行** C++ / C# / Rust / ... 的测试驱动 | ✅ **必须** |

### 2.7 常见误解

- ❌ "代码生成完就能直接调用。" → **不行**。桥接程序必须运行。
- ❌ "我在 GUI 里只生成代码，所以不需要桥接程序。" → **生成阶段确实不需要**。但一旦**运行**生成的代码或打开测试页，就需要。
- ❌ "桥接程序和服务是二选一。" → **两者必须同时运行**。
- ❌ "桥接程序只需要运行一次，然后就能关掉。" → **关掉桥接程序就等于关掉整条 HTTP↔RPC 通路**。
- ❌ "MCP 服务和桥接程序是同一个东西。" → **不是**。MCP 服务让智能体调用本工具生成代码；桥接程序让生成的代码能调用服务。**两者不能互相替代**。
- ❌ "没有 `.md` 就没法知道怎么构建。" → **不是**。CMake 脚本、`setup_*_tests.ps1`、测试驱动、桩签名、生成代码顶部注释块共同承载了原本 `.md` 里的全部信息。见第 3 章与第 14 章。

> **请记住一句话：桥接程序（`bridge.py` / `bridge.exe`）是转发器，必须始终运行。**

### 2.8 桥接程序的启动命令速查

```bash
# 最简形式（假定 bridge.py 在 PATH 上）
python3 bridge.py --endpoint ipc:<UnitName>_http_json --port 8081 --no-precheck

# 指定 Python 可执行文件
python3 /path/to/bridge.py --endpoint ipc:<UnitName>_http_json --port 8081 --no-precheck

# Windows
python.exe bridge.py --endpoint ipc:<UnitName>_http_json --port 8081 --no-precheck

# 使用生成的启动脚本（工具链会产出 launch_bridge.ps1）
.\launch_bridge.ps1 -PyDir D:\LingoFuse\python\lingofuse -UnitName <UnitName>
```

**参数说明**：

| 参数 | 说明 |
|------|------|
| `--endpoint` | 与服务侧**完全相同**的 LingoFuse 端点 |
| `--port` | 桥接程序的 HTTP 监听端口。默认 8081 |
| `--no-precheck` | 跳过启动时的 API 预检查。**强烈推荐**，因为预检查缓存更新有延迟 |
| `--bridge-app` | 覆盖桥接程序默认的 LingoFuse App 名（默认 `__lf_http_bridge__`） |
| `--bridge-api` | 覆盖桥接程序默认的 LingoFuse API 名（默认 `__lf_outbound_post__`） |

---

## 第 3 章　接口契约从哪里读

> **新版本没有 `.md` 产物。** 接口契约必须从生成代码、CMake 脚本、测试驱动、桩签名读取。本章把这九类契约逐一展开。

### 3.1 从桩签名读参数与返回类型

**桩（stub）是接口的最终定义。** 每个支持例程对应一个 `internal_call_<Api>` 桩。**桩的签名 = 线上契约的精确对偶。**

#### 3.1.1 Pascal 桩

```pascal
// 生成的文件：<U>_http_json_service_unit.pas
function internal_call_Add_Add(a: Int64; b: Int64): Int64;
begin
  // TODO: call the real function, for example:
  //   Result := Add(a, b);
  Result := 0;
end;
```

**读法**：

- **API 名**：`Add`（`internal_call_Add_Add` 的两段 `Add` 分别表示原始例程名与规范化 ApiName）。
- **参数**：`a: Int64`、`b: Int64`。
- **返回**：`Int64`。

#### 3.1.2 Python 桩

```python
# 生成的文件：<U>_http_json_service.py
def internal_call_Add(a: int, b: int) -> int:
    """
    HTTP/JSON API: Add.

    TODO: replace the body with a call to the real implementation.
    Suggested call: Add(a, b)
    """
    # TODO: implement this stub.
    return 0
```

**读法**：

- **API 名**：`Add`。
- **参数**：`a: int`、`b: int`。
- **返回**：`int`。
- **推荐调用形式**：`Add(a, b)`。

#### 3.1.3 C++ 桩

```cpp
// 生成的文件：<U>_http_json_service.cpp
std::int64_t internal_call_Add(std::int64_t a, std::int64_t b) {
    // TODO: implement this stub.
    // Suggested call: Add(a, b);
    return 0;
}
```

#### 3.1.4 C# 桩

```csharp
// 生成的文件：<U>_http_json_service.cs
public static long Add(long a, long b)
{
    // TODO: replace the body with a call to the real implementation.
    // Suggested call: Add(a, b);
    return 0;
}
```

#### 3.1.5 Rust 桩

```rust
// 生成的文件：<U>_http_json_service_rs.rs
pub fn internal_call_Add(a: i64, b: i64) -> i64 {
    let _ = (a, b);
    // TODO: replace this body with the real implementation.
    0
}
```

#### 3.1.6 Go 桩

```go
// 生成的文件：<U>_http_json_service_go.go
func internalCallAdd(a int64, b int64) (int64, error) {
    _ = a
    _ = b
    // TODO: replace this body with the real implementation.
    return 0, nil
}
```

#### 3.1.7 Rust 服务侧的 `extract_*` 辅助

Rust 服务侧的桩签名直接反映参数类型。同时生成了一组 `extract_i64` / `extract_f64` / `extract_string` 辅助函数，用来把 JSON 值转换为 Rust 类型。**这些辅助函数的返回类型就是线上参数的允许 JSON 类型**：

| 辅助函数 | 接受 JSON 类型 | 拒绝 JSON 类型 |
|----------|----------------|----------------|
| `extract_i64` | 整数 | 浮点（会报错"not an integer"） |
| `extract_f64` | 整数或浮点 | 字符串、布尔 |
| `extract_string` | 字符串 | 数字、布尔 |

**读法结论**：桩签名直接映射到线上类型——`i64` → JSON integer；`f64` → JSON number；`&str` → JSON string。

### 3.2 从注册表读 API 名

**注册表是 API 名的唯一权威来源。** 生成的注册函数会依次调用 `LF_RegisterCallEx` / `app.registerCall` / `app.register_call`（各语言语法不同）。**第一个参数就是线上 API 名。**

#### 3.2.1 Pascal 注册

```pascal
// 生成的文件：<U>_http_json_service_unit.pas
procedure RegisterAllHTTPJsonAPIs(App: TAppHnd___);
begin
  LF_RegisterCallEx(App, 'Add',  'Adds two integers and returns the sum.', nil, @Callback_Add);
  LF_RegisterCallEx(App, 'Sub',  'Subtracts b from a.',                  nil, @Callback_Sub);
end;
```

#### 3.2.2 Python 注册

```python
# 生成的文件：<U>_http_json_service.py
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

#### 3.2.3 C++ 注册

```cpp
// 生成的文件：<U>_http_json_service.cpp
void register_all_http_json_apis(lingofuse::App& app) {
    if (!app.registerCall("Add", "Adds two integers and returns the sum.",
                          nullptr, Callback_Add)) { /* ... */ }
    if (!app.registerCall("Sub", "Subtracts b from a.",
                          nullptr, Callback_Sub)) { /* ... */ }
}
```

#### 3.2.4 Rust 注册

```rust
// 生成的文件：<U>_http_json_service_rs.rs
pub fn register_all_apis(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    app.register_call("Add", "Adds two integers and returns the sum.", cb_Add)?;
    app.register_call("Sub", "Subtracts b from a.", cb_Sub)?;
    Ok(())
}
```

**读法结论**：`'Add'` / `'Sub'` 等就是 HTTP 路径段 `<api-name>`，URL 形如 `http://.../<app-name>/Add`。

### 3.3 从生成代码顶部注释块读语言特定配置

**每份生成代码的顶部都有一块固定的注释块**，说明该语言的依赖、构建、运行方式、线上协议。**这是 `.md` 移除后最重要的一手信息来源。**

#### 3.3.1 C++ 服务顶部注释（节选）

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

**读法**：

- **线上协议**（请求形状、响应形状）。
- **依赖关系**（"LingoFuse.h 来自 LingoFuse.hpp"）。
- **禁止事项**（"不要重定义 LF_CDECL"）。

#### 3.3.2 Rust 调用侧顶部注释（节选）

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

**读法**：

- **`Cargo.toml` 依赖**（直接可复制）。
- **使用方式**（crate root 还是子模块）。
- **同步 / 异步入口**（`fn main()` vs `#[tokio::main] async fn main()`）。

#### 3.3.3 Zig 调用侧顶部注释（节选）

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

**读法**：

- **进程拓扑**（Zig → bridge → service）。
- **生命周期契约**（必须先 `init()`，退出前 `deinit()`）。

### 3.4 从 CMakeLists.txt 读构建契约

**`CMakeLists.txt` 是 C++ 构建的唯一权威。** 它定义了：

1. **目标名**：`<U>_http_json_service` 与 `<U>_http_json_call_test`。
2. **源文件**：`<U>_http_json_service.cpp`、`<U>_http_json_call.cpp`、`test_main___.cpp`、`LingoFuse.c`。
3. **包含目录**：项目目录 + `LINGOFUSE_CPP_LIB_DIR`。
4. **链接库**：Windows 上 `ws2_32`；其他平台 `Threads::Threads` + `${CMAKE_DL_LIBS}`。
5. **C++ 标准**：17。
6. **必需变量**：`LINGOFUSE_CPP_LIB_DIR`（可缓存 PATH，默认空）。

#### 3.4.1 关键片段

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

#### 3.4.2 读法

- **必须设置 `-DLINGOFUSE_CPP_LIB_DIR=/path/to/lf`**，否则 configure 阶段立刻 `FATAL_ERROR`。
- **两个可执行文件**：`<U>_http_json_service` 和 `<U>_http_json_call_test`。
- **`test_main___.cpp` 与 `<U>_http_json_call.cpp` 属于同一个 target**——它们必须一起编译。
- **`LingoFuse.c` 属于两个 target**——它是 C 源，所以 CMake 里 `project()` 必须声明 `C CXX`。

### 3.5 从 test_main___.cpp 读调用示例

**`test_main___.cpp` 是调用方式的最权威示例。** 它依次调用每个生成的函数并打印 `OK` / `FAILED`。

#### 3.5.1 关键片段

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
        // ... 等待 future
    }

    lingofuse::exitMainThread();
    lingofuse::shutdown();
    return failures == 0 ? 0 : 1;
}
```

#### 3.5.2 读法

- **`prepareClient` 的参数就是 `ENDPOINT`**：`"ipc:<U>_http_json"`。
- **`prepareDone()` 必须返回 1**，否则框架已启动或失败。
- **`HTTP_CALL_BASE_URL` 的默认值是 `"http://127.0.0.1:8081/<U>"`**，与桥接程序端口一致。
- **同步调用的签名**：`<U>::Add(1, 2)`——直接返回结果，失败抛异常。
- **异步调用的签名**：`<U>::Add_Async(1, 2, callback)`——立即返回，结果通过 callback 送达。
- **失败路径的唯一形态**：`HTTPCallError`。

### 3.6 从各语言测试驱动读调用示例

**测试驱动就是调用示例。** 每个 `*_main_test___.*` 文件按顺序调用每个 API 并打印 `OK` / `FAILED`。

| 语言 | 测试驱动文件名 | 核心调用形态 |
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

**读法**：把测试驱动里的 "0" 换成你自己的参数值即可。

### 3.7 从 setup_*_tests.ps1 读环境准备契约

**各语言的测试环境准备脚本是 `.ps1`**。它们承载了"运行测试前需要做什么"。

#### 3.7.1 `setup_js_tests.ps1`（Node.js）

核心步骤：

1. 验证 `node` / `npm` 在 PATH。
2. 检查四个生成文件是否存在。
3. `npm install` `lingofuse-js`。
4. 可选 `-RunSmoke` 运行 `node .\<U>_http_json_service_main_test___.js --smoke`。

#### 3.7.2 `setup_ts_tests.ps1`（TypeScript）

核心步骤：

1. 验证 `node` / `npm`。
2. 检查四个生成文件。
3. `npm install` `lingofuse-ts` + `tsx`。
4. 可选 `-RunSmoke` 运行 `.\node_modules\.bin\tsx.cmd .\<U>_http_json_service_main_test___.ts --smoke`。

#### 3.7.3 `setup_zig_tests.ps1`（Zig）

核心步骤：

1. 验证 `zig` 在 PATH。
2. 创建 `zig_service_test/` 与 `zig_call_test/` 两个 Zig 工程。
3. 把生成的 `.zig` 复制进去。
4. 写 `build.zig` 与 `build.zig.zon`。

#### 3.7.4 `setup_erlang_tests.ps1`（Erlang）

核心步骤：

1. 验证 `erlc` / `escript` 在 PATH。
2. 复制 `lingofuse*.beam` 到 `ebin/`。
3. 复制 `lingofuse_nif.dll` 到 `priv/`。
4. `erlc -o ebin <U>_http_json_service.erl <U>_http_json_call.erl`。

#### 3.7.5 `setup_fortran_tests.ps1`（Fortran）

核心步骤：

1. 验证 `gfortran` / `g++` / `gcc`。
2. 编译 `lf_fortran_mod.f90`、`lf_fortran.cpp`、`LingoFuse.c`。
3. 编译 `<U>_http_json_service_mod.f90`、`<U>_http_json_call_mod.f90`。
4. 编译两个测试驱动。
5. 链接 `service_test.exe` 与 `call_test.exe`。

#### 3.7.6 `setup_julia_tests.ps1`（Julia）

核心步骤：

1. 验证 `julia`。
2. 若 `lingofuse` Julia 包缺 `Project.toml`，自动创建。
3. `Pkg.develop(path=...)` 把 `lingofuse` 装进当前项目。
4. `Pkg.add("JSON3")`、`Pkg.instantiate()`、`Pkg.precompile()`。

#### 3.7.7 `setup_r_tests.ps1`（R）

核心步骤：

1. 验证 `R` / `Rscript`。
2. 验证 `lingofuse`、`jsonlite`、`httr`、`future` 四个 R 包。
3. `-InstallMissing` 时自动安装缺失包。
4. 可选 `-RunSmoke` 运行 `Rscript -e "parse(<U>_http_json_service.R)"` 做纯语法检查。

**读法结论**：如果你要手动准备环境，直接读对应 `setup_*_tests.ps1` 的源码；里面的每一步都在做什么，一看就懂。

### 3.8 从 launch_bridge.ps1 读桥接启动契约

**`launch_bridge.ps1` 是桥接程序启动脚本**。它承载了：

1. **必需的 `-PyDir` 参数**（`bridge.py` 所在目录）。
2. **可选的 `-UnitName` / `-Endpoint` / `-Port` / `-PyExe` / `-NoPrecheck` / `-DryRun`**。
3. **端点自动推导**：`ipc:<UnitName>_http_json`。
4. **`--no-precheck` 的推荐使用**。

**核心调用形式**：

```powershell
.\launch_bridge.ps1 -PyDir D:\LingoFuse\python\lingofuse -UnitName Calculator
```

**读法结论**：不想手写 `python bridge.py ...` 时，直接调这个脚本。

### 3.9 从生成代码的常量声明读配置默认值

**每份生成代码都声明了默认的配置常量。** 这些常量直接对应该语言的"用户可改配置"。

#### 3.9.1 Pascal 调用侧

```pascal
// 生成的文件：<U>_http_json_call_unit.pas
var
  HTTP_CALL_BASE_URL: string = 'http://127.0.0.1:8081/<U>';
  HTTP_CALL_TIMEOUT_MS: Integer = 30000;
```

#### 3.9.2 Python 调用侧

```python
# 生成的文件：<U>_http_json_call.py
HTTP_CALL_BASE_URL = 'http://127.0.0.1:8081/<U>'
HTTP_CALL_TIMEOUT = 30.0
DEBUG_LOG = False
```

#### 3.9.3 C++ 调用侧

```cpp
// 生成的文件：<U>_http_json_call.cpp
std::string HTTP_CALL_BASE_URL = "http://127.0.0.1:8081/<U>";
std::string HTTP_BRIDGE_APP_NAME = "";
std::string HTTP_BRIDGE_API_NAME = "";
std::uint64_t HTTP_CALL_TIMEOUT_MS = 0;
double HTTP_CALL_DEFAULT_TIMEOUT_S = 0.0;
```

#### 3.9.4 Rust 调用侧

```rust
// 生成的文件：<U>_http_json_call_rs.rs
pub const DEFAULT_BASE_URL: &str = "http://127.0.0.1:8081/<U>";
pub const DEFAULT_TIMEOUT_SECS: u64 = 30;
// 运行时可通过 set_base_url() / set_timeout_secs() 修改
```

#### 3.9.5 Go 调用侧

```go
// 生成的文件：<U>_http_json_call_go.go
const DefaultBaseURL = "http://127.0.0.1:8081/<U>"
var HTTPCallBaseURL = DefaultBaseURL
var HTTPCallTimeout = 30 * time.Second
```

#### 3.9.6 Ruby 调用侧

```ruby
# 生成的文件：<U>_http_json_call.rb
module CalculatorHttpJsonCall
  @base_url = "http://127.0.0.1:8081/<U>"
  @http_call_timeout = 30.0
  @debug_log = (ENV['LINGOFUSE_DEBUG'] == '1') || (ENV['LINGOFUSE_DEBUG'] == 'true')

  class << self
    attr_accessor :base_url
    attr_accessor :http_call_timeout
    attr_accessor :debug_log
    # 只读兼容读取器：
    def HTTP_CALL_BASE_URL; @base_url; end
    def HTTP_CALL_TIMEOUT; @http_call_timeout; end
    def DEBUG_LOG; @debug_log; end
  end
end
```

**注意 Ruby 的陷阱**：`HTTP_CALL_BASE_URL` 是**只读**的。赋值给它会被 Ruby 解析为常量赋值，抛出 `dynamic constant assignment`。请用 `Module.base_url = "..."`。

#### 3.9.7 Julia 调用侧

```julia
# 生成的文件：<U>_http_json_call.jl
module CalculatorHttpJsonCall
  HTTP_CALL_BASE_URL::String = "http://127.0.0.1:8081/<U>"
  HTTP_BRIDGE_APP_NAME::String = ""
  HTTP_BRIDGE_API_NAME::String = ""
  HTTP_CALL_TIMEOUT_MS::Int64 = Int64(0)
  HTTP_CALL_DEFAULT_TIMEOUT_S::Float64 = 0.0
end
```

**Julia 的访问方式**：`CalculatorHttpJsonCall.HTTP_CALL_BASE_URL = "..."`（模块变量直接赋值）。

### 3.10 接口契约获取入口对照表（速查）

| 契约 | Pascal | Python | C++ | C# | Rust | Go | Java | Ruby | R | Julia | Swift | Zig |
|------|:------:|:------:|:---:|:--:|:----:|:--:|:----:|:----:|:-:|:-----:|:-----:|:---:|
| **API 名** | 注册表 | 注册表 | 注册表 | 注册表 | 注册表 | 注册表 | 注册表 | 注册表 | 注册表 | 注册表 | 注册表 | 注册表 |
| **参数类型** | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 |
| **返回类型** | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 | 桩签名 |
| **调用示例** | 测试驱动 | 测试驱动 | `test_main___.cpp` | 测试驱动 | 测试驱动 | 测试驱动 | 测试驱动 | 测试驱动 | 测试驱动 | 测试驱动 | 测试驱动 | 测试驱动 |
| **构建命令** | `fpc` + `-Fu` | `python3` | `CMakeLists.txt` | `dotnet` | `cargo` | `go` | `javac` | `ruby` | `Rscript` | `julia` | `swift` | `zig` |
| **环境变量** | 顶部注释 | 顶部注释 | 顶部注释 | 顶部注释 | 顶部注释 | 顶部注释 | 顶部注释 | 顶部注释 | 顶部注释 | 顶部注释 | 顶部注释 | 顶部注释 |
| **默认 Base URL** | `HTTP_CALL_BASE_URL` | `HTTP_CALL_BASE_URL` | `HTTP_CALL_BASE_URL` | `HttpJsonCallConfig.BaseUrl` | `DEFAULT_BASE_URL` | `DefaultBaseURL` | `HTTP_CALL_BASE_URL` | `@base_url` | `HTTP_CALL_BASE_URL` | `HTTP_CALL_BASE_URL` | `baseUrl` | `DEFAULT_BASE_URL` |
| **默认超时** | `HTTP_CALL_TIMEOUT_MS` | `HTTP_CALL_TIMEOUT` | `HTTP_CALL_DEFAULT_TIMEOUT_S` | `HttpJsonCallConfig.HttpTimeoutSec` | `DEFAULT_TIMEOUT_SECS` | `HTTPCallTimeout` | `HTTP_CALL_TIMEOUT` | `@http_call_timeout` | `HTTP_CALL_DEFAULT_TIMEOUT_S` | `HTTP_CALL_DEFAULT_TIMEOUT_S` | `timeout` | `DEFAULT_HTTP_TIMEOUT_SEC` |

**读法**：先读桩签名确定接口，再读测试驱动确定调用形态，再读 CMake 脚本 / `setup_*_tests.ps1` 确定构建方式，最后读顶部注释块确定环境变量。

---

## 第 4 章　环境准备

### 4.1 直接运行工具本身

在可执行文件所在目录运行 `code_decl_to_json_abi`。程序会在自身旁边查找以下文件：

- `pascal_code_abi_rule.md`（Pascal 原型规则）
- `C_code_abi_rule.md`（C 原型规则）

**缺失它们不会阻塞使用**；只是让 GUI 的"规则文档"按钮失效。

> **注意**：这两份 `*_rule.md` **不是生成产物**。它们是工具自带的规则文件，由工具作者维护，与 `.md` 生成功能无关。**移除的是产物 README，不是这两份规则文件。**

### 4.2 生成阶段的依赖

- **生成阶段（GUI / CLI / MCP）没有额外依赖。** 工具本身不联网、不使用桥接程序。
- **运行生成的代码 / 测试页**时才需要桥接程序与服务侧。

### 4.3 运行阶段的依赖

| 组件 | 用途 | 是否必需 |
|------|------|:--------:|
| **服务侧**（用生成的 `*_service_*` 代码编译而来） | 提供业务逻辑 | ✅ 必需 |
| **桥接程序**（`bridge.py` 或 `bridge.exe`） | HTTP ↔ RPC 转发 | ✅ **必须始终运行** |
| **调用侧**（用生成的 `*_call_*` 代码编译而来，或 HTML 测试页） | 发起调用 | 按需 |

### 4.4 C++ 目标的依赖

本工具链生成的 CMake 脚本需要：

- **CMake 3.15** 或更高版本。
- **同时具备 C 与 C++ 编译器**（工程声明 `project(<name> C CXX)`）。
- **LingoFuse C++ 发行目录**，通过 `LINGOFUSE_CPP_LIB_DIR` 指定。该目录必须包含：
  - `LingoFuse.h`
  - `LingoFuse.c`
  - `LingoFuse.hpp`
  - `lf_io.hpp`
  - `lf_http_bridge_client.hpp`
  - `json.hpp`

### 4.5 C# 目标的依赖

生成的 C# 产物需要：

- **.NET 8.0** 或更高版本。
- **LingoFuse .NET 绑定**（`LingoFuse.dll`）。
- **LingoFuse 原生库**（`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`）与 `z_ipc_*`。

### 4.6 Rust 目标的依赖

生成的 Rust 产物需要：

- **Rust 1.70+**。
- 以下 crate（调用侧）：`ureq`、`reqwest`、`tokio`、`serde_json`。
- 以下 crate（服务侧）：`lingofuse`、`serde_json`。

### 4.7 Go 目标的依赖

生成的 Go 产物需要：

- **Go 1.21+**。
- 调用侧：仅标准库。
- 服务侧：`github.com/PassByYou888/LingoFuse/go`。

### 4.8 Java 目标的依赖

生成的 Java 产物需要：

- **JDK 11+**（推荐 17+）。
- 调用侧 / 测试：`com.fasterxml.jackson.core:jackson-databind`。
- 服务侧：`lingofuse` Java 包。

### 4.9 Node.js / TypeScript 目标的依赖

- **Node.js 18+**（Node 18 起 `fetch` 内置）。
- 调用侧：仅标准库。
- 服务侧：`lingofuse-js`（Node.js）或 `lingofuse-ts`（TypeScript）。
- TypeScript 测试：`tsx` 命令行工具。

### 4.10 Ruby 目标的依赖

- **Ruby 2.7+**（推荐 3.0+）。
- 服务侧：`lingofuse` gem（编译期需要 C 扩展工具链）。
- 调用侧：仅标准库（`net/http`、`json`、`uri`）。

### 4.11 R 目标的依赖

- **R 4.0+**。
- 服务侧：`lingofuse`、`jsonlite`。
- 调用侧：`lingofuse`、`jsonlite`、`httr`、`future`。

### 4.12 Julia 目标的依赖

- **Julia 1.9+**（推荐 1.10+）。
- 必须以 `--threads=2` 或更多启动 Julia。
- `LingoFuse`、`JSON3` 包。

### 4.13 Erlang 目标的依赖

- **Erlang/OTP 25+**。
- 服务侧：`lingofuse` Erlang binding（含 `lingofuse_nif.dll`）。

### 4.14 Fortran 目标的依赖

- **gfortran 9+** 或 **ifort / flang**。
- 服务侧：`lf_fortran_mod.f90` + `lf_fortran.cpp`。

### 4.15 智能体模式的依赖

智能体模式需要 LingoFuse 运行时：

- `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`
- `z_ipc_*.dll` / `libz_ipc_*.so`
- 一个在线的 Beacon 服务（`agent_main_app`）

如果你只用本地 GUI / CLI，**不需要这些运行时依赖**。

### 4.16 验证依赖是否就绪

| 语言 | 验证命令 |
|------|----------|
| C++ | `cmake --version`、`g++ --version` 或 `cl.exe` |
| Rust | `rustc --version`、`cargo --version` |
| Go | `go version` |
| Java | `java -version`、`javac -version` |
| Node.js | `node --version`、`npm --version` |
| TypeScript | `npx tsc --version` 或 `npx tsx --version` |
| Ruby | `ruby --version`、`gem list lingofuse` |
| R | `Rscript -e 'cat(R.version.string)'` |
| Julia | `julia --version`、`julia -e 'using Pkg; Pkg.status()'` |
| Erlang | `erl -version`、`escript --version` |
| Fortran | `gfortran --version` |
| Zig | `zig version` |
| PHP | `php --version`、`php -m \| grep curl` |
| Swift | `swift --version` |
| Dart | `dart --version` |

**所有依赖都满足之后，再进入第 5 章（GUI）或第 6 章（CLI）。**

---

## 第 5 章　GUI 操作指南

### 5.1 启动 GUI

**不带任何命令行参数运行可执行文件**。GUI 直接打开。

GUI 有 5 个顶层标签页，从左到右依次推进：

```
[1. Welcome] → [2. Source Code] → [3. Source ↔ JSON] → [4. JSON ↔ Model] → [5. Final Source]
```

每个标签页顶部有一排"上一步 / 下一步"按钮，底部面板显示实时 `DoStatus` 日志。

启动时，表单还会在后台线程上静默启动 **MCP 服务**（见第 7 章）。

### 5.2 页 1 — Welcome

- 显示工具的整体介绍、架构图、工作流。
- 右侧按钮：
  - **Pascal rule doc** — 打开 `pascal_code_abi_rule.md`。
  - **C rule doc** — 打开 `C_code_abi_rule.md`。
- **Next: Enter source code** — 跳到页 2。

### 5.3 页 2 — Source Code

这一页是你**输入代码**的地方。

**顶部工具栏**：

| 控件 | 用途 |
|------|------|
| **Select Language label** | 点击自动检测源语言。 |
| **Language Selector 下拉框** | `Auto-detect` / `Pascal` / `C`，手动选择。 |
| **Format** | 只保留顶层函数，重建最小声明。 |
| **Empty unit** | 插入最小骨架（Pascal 或 C）。 |
| **Test unit** | 插入覆盖多种语法形式的复杂样例（推荐首次运行时先看这个）。 |
| **Next: Pascal/C → JSON** | 解析当前源，产出 LV0 JSON，跳到页 3。 |

**操作步骤**：

1. 把你的 Pascal 单元或 C 头文件粘贴进编辑器。
2. 如果不确定语言，点击 **Select Language** 让工具检测。
3. 如果语法高亮看起来不对，从下拉框手动选择语言。
4. 点击 **Next: Pascal/C → JSON**。

### 5.4 页 3 — Source ↔ JSON

这一页显示**原始解析输出（LV0）**。

| 按钮 | 用途 |
|------|------|
| **Back: rebuild code from JSON** | 用当前 JSON 重建源代码，写回页 2。 |
| **Next: JSON ↔ Model** | 把 LV0 规范化成 LV1 Model，跳到页 4。 |

你可以**在这里手动纠正 JSON**——比如解析器把某个类型分类错了，直接改 JSON 里的字符串，然后点 **Next** 继续。

### 5.5 页 4 — JSON ↔ Model

这一页显示**规范化后的模型 JSON（LV1）**。

| 按钮 | 用途 |
|------|------|
| **Back: JSON ↔ Model** | 把 LV1 反向还原成 LV0，写回页 3。 |
| **Next: generate source** | 生成全部产物，跳到页 5。 |

**提示**：模型 JSON 会自动丢弃不支持的类型（`Boolean`、`Variant`、数组、记录、类、接口、枚举、集合、指针、`Currency`、`TDateTime` 等）。如果某个函数没有出现在最终产物里，几乎总是因为它的参数或返回值里有不支持的 ABI 类型。

### 5.6 页 5 — Final Source

这一页有 **9 个以上的子标签**，每个显示**一个编辑器**（**不再有配套 `.md` 编辑器**）：

| 子标签 | 内容 |
|--------|------|
| Pascal Service | Pascal 服务代码 |
| Pascal Call | Pascal 调用代码 |
| JavaScript Call | JS 客户端代码 |
| JavaScript Test HTML | 自包含 HTML 测试页 |
| Python Service | Python 服务代码 |
| Python Call | Python 调用代码 |
| C# Service | C# 服务代码 |
| C# Call | C# 调用代码 |
| C# Test | 服务测试驱动 + 调用测试驱动 |
| C++ Service | C++ 服务 `.hpp` + `.cpp` |
| C++ Call | C++ 调用 `.hpp` + `.cpp` |
| **CMake** | **`CMakeLists.txt` + `test_main___.cpp`** |
| （其他已注册语言） | 对应语言的代码 / 测试 |

> **`.md` 编辑器已被移除。** 想在 GUI 里读接口契约，直接切到对应语言的子标签，**读代码顶部的注释块**。见第 3 章。

**文件已经写入磁盘**：生成时，所有产物会自动写入可执行文件目录的 `<UnitName>/` 子目录。

顶部按钮：

- **Back: Model JSON** — 回到页 4 继续调整模型。

### 5.7 生成的"文件列表"在哪里

**`final_source_file_ListView`** 是 GUI 里的产物列表。每一项含：

- `Caption`：文件名。
- `SubItems[0]`：完整路径。

**MCP 层的 `ListFiles` 与 `GetFile` 就读这个 ListView**。它由 `GenerateAllSourcesClick` 填充，每次生成前清空。

### 5.8 CMake 子标签

CMake 子标签显示两份固定名产物：

- `CMakeLists.txt` — CMake 构建脚本。
- `test_main___.cpp` — C++ 调用测试驱动。

这两份文件写入 `<exe 目录>/<UnitName>/`，正是 C++ 构建所需的文件。**把它们（以及 `.hpp`/`.cpp` 对）从这个标签页复制出来（或从磁盘目录复制）**，CMake 工程就完整了。

### 5.9 C# Test 子标签

C# Test 子标签显示两份 C# 测试产物：

- `<Unit>_http_json_service_main_test___.cs` — 服务侧测试程序。
- `<Unit>_http_json_call_main_test___.cs` — 调用侧测试程序。

两个测试程序都设计为复制进 `dotnet new console` 项目作为 `Program.cs`，与对应的服务或调用模块一起使用。

### 5.10 日志面板

底部面板是实时 `DoStatus` 日志。它显示：刚保存了哪个文件、规范化时丢弃了哪些函数、生成器报了什么错。超过 5000 行时自动清空。

### 5.11 从 GUI 里读接口契约

1. **桩签名** → 打开对应语言的 Service 子标签，找 `internal_call_<Api>` 桩。
2. **API 名** → 在同一个文件里搜 `LF_RegisterCallEx` / `app.registerCall` / `app.register_call`。
3. **调用示例** → 打开对应语言的 Test 子标签。
4. **构建命令** → 打开 CMake 子标签（C++）或读对应语言测试驱动的顶部注释。
5. **默认 Base URL / 超时** → 打开对应语言的 Call 子标签，找常量声明。

---

## 第 6 章　命令行操作指南

### 6.1 触发条件

命令行模式**只在至少传入一个参数时触发**。无参数 = GUI。

程序编译为控制台子系统，因此：

- 双击 = 启动 GUI（系统可能弹出一个额外的空控制台窗口；关闭主窗口即结束）。
- 命令行运行 = 所有 `DoStatus` 消息直通 stdout，正常完成通过退出码返回。

### 6.2 语法

```
code_decl_to_json_abi --help
code_decl_to_json_abi <input_file> <output_file>
code_decl_to_json_abi --call <input_file> <output_file>
code_decl_to_json_abi --lang <language_id> <input_file> <output_file>
```

| 参数 | 说明 |
|------|------|
| `--help` / `-h` / `-?` / `/?` | 打印帮助并退出。**仅识别为第 1 个参数。** |
| `--call` / `-c` | 生成调用侧。**仅识别为第 1 个参数**；默认是服务侧。 |
| `--lang <id>` / `-l <id>` | 强制指定目标语言。可选值见 `--list-languages`。 |
| `--list-languages` / `-ll` | 列出所有已注册的目标语言。 |
| `<input_file>` | 输入源文件。语言由**扩展名**决定。 |
| `<output_file>` | 输出文件。目标语言由**扩展名**决定（若未传 `--lang`）。 |

### 6.3 输入扩展名 → 源语言

| 扩展名 | 源语言 |
|--------|--------|
| `.pas` / `.pp` / `.p` | Pascal |
| `.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx` | C |

### 6.4 输出扩展名 → 目标语言

| 扩展名 | 目标语言 | 支持的方向 |
|--------|----------|------------|
| `.pas` / `.pp` / `.p` | Pascal | Service + Call |
| `.py` | Python | Service + Call |
| `.hpp` / `.hh` / `.h` / `.cpp` / `.cc` / `.cxx` / `.c` | C++（`.hpp` + `.cpp` 双文件 + CMake） | Service + Call |
| `.cs` | C#（服务代码 + 调用代码 + 测试程序） | Service + Call + Test |
| `.js` | JavaScript | **仅 Call 侧** |
| `.node.js` / `_node.js` | Node.js | Service + Call |
| `.ts` | TypeScript | Service + Call |
| `.go` | Go | Service + Call |
| `.rs` | Rust | Service + Call |
| `.java` | Java | Service + Call |
| `.dpr` / `.dproj` | Delphi | **仅 Call 侧** |
| `.dart` | Dart | Service + Call |
| `.swift` | Swift | Service + Call |
| `.rb` | Ruby | Service + Call |
| `.zig` | Zig | Service + Call |
| `.erl` | Erlang | Service + Call |
| `.f90` | Fortran | Service + Call |
| `.jl` | Julia | Service + Call |
| `.r` / `.R` | R | Service + Call |
| `.php` | PHP | **仅 Call 侧** |

**JavaScript 与 PHP 是调用侧专属**：不给 `--call` 直接输出 `.js` 或 `.php`，会立刻以参数错误退出。

### 6.5 每次运行产出什么

以 `<output>` 的基名（去掉扩展名）为准，工具写入**同目录**：

- **代码文件**：`<base>.xxx`（Pascal / Python / JS / C# / Rust / Go / Java / Ruby / Erlang / Julia / R 单文件；C++ 产出 `<base>.hpp` + `<base>.cpp` 双文件）。
- **配套测试程序**：`<base>_main_test___.xxx`（部分语言，见附录 G）。
- **JS 专属**：额外产出 `<base>_test.html`（自包含测试页）。
- **C++ 专属**：额外产出 `CMakeLists.txt` 与 `test_main___.cpp`（**固定名，无 base 前缀**）。
- **Node.js / TypeScript 专属**：额外产出 `setup_js_tests.ps1` / `setup_ts_tests.ps1`。
- **R / Julia / Erlang / Fortran / Zig 专属**：额外产出 `setup_<lang>_tests.ps1`。
- **Bridge 专属**：`launch_bridge.ps1`。
- **⚠️ 不再产出 `<base>_readme.md`。**

> **关于 C++ 固定名**：`CMakeLists.txt` 与 `test_main___.cpp` 是 C++ 构建所需的精确名字。把两个不同的单元生成到同一目录会覆盖前一次的 CMake 文件。**一个目录一个单元。**

### 6.6 示例

**服务：Pascal → Pascal**

```
code_decl_to_json_abi calculator.pas calculator_service.pas
```

产物：

```
calculator_service.pas
```

（测试程序 `<base>_main_test___.pas` 由 test 生成器独立产出，见附录 G 的产物对应关系；CLI 单次运行产出 service + call 中对应的一侧。）

**调用：Pascal → Pascal**

```
code_decl_to_json_abi --call calculator.pas calculator_call.pas
```

**服务：C → Python**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_service.py
```

**调用：C → Python**

```
code_decl_to_json_abi --call ComplexTestUnit.h calculator_call.py
```

**服务：C → C++（`.hpp` + `.cpp` + CMake）**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_service.hpp
```

产物：

```
calculator_service.hpp
calculator_service.cpp
CMakeLists.txt
test_main___.cpp
```

**服务：C → C#（工程 + 测试）**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_project.cs
```

产物（全部写入输出文件所在目录）：

```
ComplexTestUnit_http_json_service.cs
ComplexTestUnit_http_json_call.cs
ComplexTestUnit_http_json_service_main_test___.cs
ComplexTestUnit_http_json_call_main_test___.cs
```

**调用：C → JavaScript（`.js` + `.html`）**

```
code_decl_to_json_abi --call ComplexTestUnit.h calculator_call.js
```

产物：

```
calculator_call.js
calculator_call_test.html
```

**服务：C → Rust**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_service.rs
```

产物：

```
calculator_service.rs
```

**调用：C → Go**

```
code_decl_to_json_abi --call ComplexTestUnit.h calculator_call.go
```

产物：

```
calculator_call.go
```

**强制目标语言（扩展名未知）**

```
code_decl_to_json_abi --lang java ComplexTestUnit.h out/Calculator
```

### 6.7 退出码

| 退出码 | 含义 |
|:------:|------|
| `0` | 转换成功。 |
| `1` | 缺少或非法参数。 |
| `2` | 源解析失败（`ParseSuccess=False`，或没找到可用声明）。 |
| `3` | 代码生成失败（某个生成器返回 `nil`）。 |
| `4` | 文件 I/O 错误（读或写失败）。 |

### 6.8 输出消息

命令行模式下，所有中间消息都写到 stdout，例如：

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

出错时打印 `Failed.` 并返回非零退出码。**不要解析文字**，依赖退出码。

### 6.9 ⚠️ CLI 不启动桥接程序

**CLI 只负责生成代码。它不启动桥接程序，也不启动服务。**

要真正跑一次端到端调用，你必须手动：

1. 编译 / 运行生成的服务侧（构建命令见第 14 章）；
2. **单独启动 `bridge.py`（或 `bridge.exe`）并保持运行**；
3. 然后运行调用侧或打开 HTML 测试页。

### 6.10 ⚠️ CLI 不再交付 `.md`——读代码

新版本**不产出 `<base>_readme.md`**。接口契约从代码本身读：

- **桩签名** → 读 service 代码。
- **调用示例** → 读 `<base>_main_test___.xxx`。
- **构建命令** → 读 `CMakeLists.txt`（C++）、`setup_*_tests.ps1`（多语言）、或第 14 章。
- **默认配置** → 读 call 代码顶部的常量声明。
- **环境变量 / 依赖** → 读生成代码顶部的注释块。

### 6.11 构建生成的 C++

当 CLI 产出 C++ 目标时，CMake 支持文件会落在 `.hpp`/`.cpp` 对旁边。典型工作流：

```bash
# 把 .hpp/.cpp 对、CMakeLists.txt、test_main___.cpp 放进一个目录。
cd 那个目录

cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

CMake 工程构建**两个可执行文件**：

- `<Unit>_http_json_service` — 服务可执行文件。
- `<Unit>_http_json_call_test` — 调用测试驱动。

CMake 脚本**不复制运行时 DLL**。把 `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` 与 `z_ipc_*` 复制到可执行文件旁边（或把它们的目录加入 `PATH` / `LD_LIBRARY_PATH`）。

### 6.12 构建生成的 C#

CLI 的 `.cs` 输出产出一个完整的 C# 工程。工作流：

```bash
# 把四份 C# 文件放进一个目录。

dotnet new console -o my_service
cd my_service
cp ../ComplexTestUnit_http_json_service.cs .
cp ../ComplexTestUnit_http_json_service_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

### 6.13 构建生成的 Rust

```bash
# 把 .rs 放进一个目录。

cargo new my_service
cd my_service
cargo add lingofuse --path ../LingoFuse/rust
cargo add serde_json
cp ../calculator_service.rs src/
cp ../calculator_service_main_test___.rs src/main.rs
cargo run
```

### 6.14 构建生成的 Go

```bash
# 把 .go 放进一个目录。

go mod init calculator
go get github.com/PassByYou888/LingoFuse/go
cp calculator_service.go .
cp calculator_service_main_test.go .
go test -v
```

### 6.15 构建生成的 Java

```bash
# 把 .java 放进一个目录。

javac -cp lingofuse.jar:jackson-databind.jar *.java
java --enable-native-access=ALL-UNNAMED -cp .:lingofuse.jar:jackson-databind.jar HttpJsonService
```

---

## 第 7 章　智能体（MCP-API）操作指南——三个工具

### 7.1 触发条件

**GUI 启动后**，工具自动在后台线程启动 MCP 服务：

1. 创建一个 LingoFuse App（默认名 `code_decl_to_json_abi_mcp_api`）。
2. 连接到 LingoFuse 端点（默认 `ipc:agent`）。
3. 通过 Beacon（默认 App `agent_main_app`，API `register_agent`）注册全部**三个工具**。

所以要让智能体调用本工具，需要满足：

- 本工具的 GUI **正在运行**；
- Beacon（如 `pascal_agent_service`）**正在运行**；
- 双方的 LingoFuse 端点一致（默认 `ipc:agent`）。

> **注意**：MCP 服务与桥接程序**是两回事**。
>
> - MCP 服务：让智能体调用本工具的三个 API（用于生成代码）。
> - 桥接程序：让所有运行期调用侧访问服务。
>
> **两者不能互相替代。** 智能体生成代码不需要桥接程序；但生成的代码一运行，**桥接程序仍必须在运行**。

### 7.2 三个工具

| # | 工具 | 用途 |
|:-:|------|------|
| 1 | `CodeDeclToJsonAbi_Generate(Source, Language)` | **第 1 步**：解析源文本，生成全部产物，返回一份包含所有文件名的清单 |
| 2 | `CodeDeclToJsonAbi_ListFiles()` | **第 2a 步**：返回产物文件名列表 |
| 3 | `CodeDeclToJsonAbi_GetFile(FileName)` | **第 2b 步**：按名字返回单个文件的完整内容 |

### 7.3 三步工作流

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
│      （对需要的文件重复 GetFile。不需要再次调用 Generate。）  │
└──────────────────────────────────────────────────────────────┘
```

### 7.4 工具 1 — `CodeDeclToJsonAbi_Generate`

**签名**：`function(Source: string; Language: string): string`

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `Source` | string | 完整源文本 |
| `Language` | string | `"pascal"` 或 `"c"`，大小写不敏感 |

**语言规则（第一大坑）**：

- `"pascal"` 表示**源文本是一份 Pascal 单元**。
- `"c"` 表示**源文本是一份 C 头文件**。
- `"python"`、`"cpp"`、`"csharp"`、`"javascript"` 是**目标**语言，**不是**源语言。传它们中的任何一个会返回：
  `{"error":"Unsupported language. Use ''pascal'' or ''c''."}`

**成功返回**（五语言口径，示例）：

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

**失败返回**：`{"error":"<message>"}`。

**失败场景**：

- `Unsupported language. Use ''pascal'' or ''c''.`
- `Form not available`
- `Generation failed: <reason>`

**注意事项**：

- 每次成功调用**替换会话**。用不同源文本再次调用 `Generate` 会丢弃上一次的一切。
- 每次成功调用**将所有产物写入磁盘**，位于 `<exe 目录>/<规范化单元名>/`。
- **一次调用产出所有目标**。没有按目标逐个 `Generate` 的接口。
- **产物清单中不含 `_readme.md`**。接口契约从代码本身读（见第 3 章）。

### 7.5 工具 2 — `CodeDeclToJsonAbi_ListFiles`

**签名**：`function(): string`

**成功返回**：

```json
{
  "status": "ok",
  "count": 20,
  "files": ["<name 1>", "<name 2>", ...]
}
```

**空返回**（如果还没调用过 `Generate`）：

```json
{"status": "ok", "count": 0, "files": []}
```

**注意事项**：

- **纯读取。** 不重跑任何生成器，不修改会话。
- 文件名是**文件名**，不是完整路径。把此列表中的某个名字作为 `GetFile` 的参数。

### 7.6 工具 3 — `CodeDeclToJsonAbi_GetFile`

**签名**：`function(FileName: string): string`

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `FileName` | string | 必须是之前 `ListFiles` 返回过的值 |

**成功返回**：

```json
{
  "status": "ok",
  "name": "<FileName>",
  "text": "<完整产物文本>"
}
```

`text` 字段包含**完整产物**，绝不截断。多行内容以标准 JSON 转义嵌入为字符串。

**失败返回**：

```json
{
  "status": "error",
  "name": "<FileName>",
  "error": "<message>"
}
```

**失败场景**：

- `Form not available`
- `File not found. Call ListFiles first to get valid names.`

**注意事项**：

- **纯读取。** 不重跑任何生成器，不修改会话。
- **`FileName` 大小写敏感。** `CMakeLists.txt` 有效；`cmakelists.txt` 无效。
- **`text` 字段可能为空**（真的是空文件时）。用 `status` 区分"空"与"错误"。

### 7.7 推荐的调用序列

**最小流程（一个目标、一份文件）**：

```
1. CodeDeclToJsonAbi_Generate(Source="...", Language="pascal")
2. CodeDeclToJsonAbi_ListFiles()
3. CodeDeclToJsonAbi_GetFile("Calculator_http_json_service_unit.pas")
```

**完整 C++ 构建准备流程**：

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

**注意**：没有第 5 步的 `.md` 要拉。**接口契约从桩签名与 `test_main___.cpp` 的调用示例读。**

**完整 C# 构建准备流程**：

```
1. CodeDeclToJsonAbi_Generate(<source>, "c")
2. CodeDeclToJsonAbi_ListFiles()
3. CodeDeclToJsonAbi_GetFile("<U>_http_json_service.cs")
4. CodeDeclToJsonAbi_GetFile("<U>_http_json_call.cs")
5. CodeDeclToJsonAbi_GetFile("<U>_http_json_service_main_test___.cs")
6. CodeDeclToJsonAbi_GetFile("<U>_http_json_call_main_test___.cs")
```

**智能体自省流程（智能体想检查自己产出了什么）**：

```
1. CodeDeclToJsonAbi_Generate(<source>, "pascal")
2. CodeDeclToJsonAbi_ListFiles()          ← 看到所有文件名
3. CodeDeclToJsonAbi_GetFile(<任意名字>)  ← 读取任意产物
```

### 7.8 智能体模式注意事项

1. **源语言只接受 `"pascal"` 或 `"c"`**；其他值一律拒绝。
2. **一次 `Generate` 产出所有目标。** 想要 Python 服务，读取 Python 命名的文件即可——不要再次调用 `Generate`。
3. **`Generate` 跨调用幂等。** 用同一份源反复调用会产出同样的产物，覆盖上一次的磁盘内容。
4. **顺序很重要**：先 `Generate`，再 `ListFiles` / `GetFile`。反过来会失败。
5. **`ListFiles` 与 `GetFile` 是纯读取。** 除非想更换会话，不要在这两步之间调用 `Generate`。
6. **GUI 必须活着。** MCP 服务随 GUI 启动附加；关闭 GUI 会让三个工具全部离线。
7. **用智能体生成代码 ≠ 运行代码。** 要真正运行生成的代码，**仍必须手动启动桥接程序并保持运行**。
8. **没有 `.md` 产物。** 智能体需要直接从代码本身读契约。推荐的读法顺序：
   - 先 `GetFile` 服务代码 → 读桩签名 → 确定 API 名、参数、返回类型。
   - 再 `GetFile` 测试驱动 → 读调用示例。
   - 若目标是 C++，`GetFile("CMakeLists.txt")` → 读目标名、源文件、链接库。
   - 若目标是多语言且有 `setup_*_tests.ps1`，`GetFile` 它 → 读环境准备步骤。
9. **C++ 目标必须拉全六份产物**：头文件 + 实现 + 测试驱动 + CMake 脚本 + 两个测试。**没有 `.md`。**
10. **C# 目标必须拉全四份产物**：服务代码 + 调用代码 + 两个测试程序。

### 7.9 示例智能体交互

```
# 1. 喂入源码并生成全部产物
CodeDeclToJsonAbi_Generate(
    Source   = "<calculator.pas 的内容>",
    Language = "pascal")
→ {"status":"ok","unit_name":"Calculator","count":20,"files":[...]}

# 2. 看看产出了什么
CodeDeclToJsonAbi_ListFiles()
→ {"status":"ok","count":20,"files":[...]}

# 3. 按需读取产物——不需要第二次 Generate
CodeDeclToJsonAbi_GetFile("Calculator_http_json_service_unit.pas")    ← 读桩签名
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call_unit.pas")       ← 读默认 Base URL
CodeDeclToJsonAbi_GetFile("Calculator_http_json_call_main_test___.pas") ← 读调用示例
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

智能体随后可以把产物转交给用户，或者在环境允许的情况下直接执行第 14 章里的构建与运行步骤。

### 7.10 智能体如何从产物中自举出构建脚本

**没有 `.md` 后，智能体的"从产物读契约"路径如下**：

```
GetFile(service code)
    → 桩签名 = API 名 + 参数类型 + 返回类型
    → 注册表 = API 名清单
    → 顶部注释 = 依赖、协议、禁止事项

GetFile(call code)
    → 默认 Base URL / 超时 / 桥接 App 名 / 桥接 API 名
    → 顶部注释 = 依赖、使用方式

GetFile(测试驱动)
    → 调用示例
    → 断言形态（OK / FAILED）

GetFile(CMakeLists.txt)  [若目标含 C++]
    → 目标名
    → 源文件清单
    → 包含目录
    → 链接库

GetFile(setup_*_tests.ps1)  [若目标语言有]
    → 环境准备步骤
    → 包安装命令
    → 测试命令
```

**智能体的"自动构建脚本"生成模板**：

```python
# 智能体的伪代码
service_src = get_file("<U>_http_json_service.<ext>")
stub_signatures = parse_stub_signatures(service_src)  # 从代码提取 API 名与类型

call_src = get_file("<U>_http_json_call.<ext>")
config = parse_config_constants(call_src)  # HTTP_CALL_BASE_URL 等

test_src = get_file("<U>_http_json_call_main_test___.<ext>")
call_examples = parse_call_examples(test_src)

# 若目标是 C++：
cmake_src = get_file("CMakeLists.txt")
targets = parse_cmake_targets(cmake_src)
sources = parse_cmake_sources(cmake_src)
link_libs = parse_cmake_link_libs(cmake_src)

# 若目标语言有 setup 脚本：
setup_src = get_file("setup_<lang>_tests.ps1")
env_steps = parse_setup_steps(setup_src)
```

---

## 第 8 章　MCP 工具提供器单元是如何构建的

本章记录**生成 `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas` 的 bootstrap → AI-fill 架构**。本章的每一句话都是关于**写工具提供器的工具**，而不是工具提供器本身。

### 8.1 三阶段构建

工具提供器单元不是手写的。它分三个阶段产出：

```
阶段 1：Bootstrap 脚本
    ↓ 产出一个结构完整的 Pascal 单元
    ↓ 含 3 个回调壳、3 个 internal-call 桩、3 个工具 schema
    ↓ 以及完整的注册脚手架
    code_decl_to_json_abi_mcp_api_tool_provider_unit.pas

阶段 2：AI 填充
    ↓ 填入每个 internal_call_* 函数体
    ↓ 含 UI 同步逻辑

阶段 3：编译 + 运行
    ↓ 该单元被编进 GUI 可执行文件
    ↓ GUI 启动时 MCP 服务注册全部 3 个工具
```

### 8.2 Bootstrap 脚本写什么

对 3 个工具中的每一个，Bootstrap 脚本写：

1. **`interface` 段中的 `function` 声明**——外部签名。
2. **`procedure Callback_...` 前向声明**——LingoFuse 将要调用的 cdecl 回调。
3. **`procedure Callback_...` 的完整函数体**——含：
   - 把输入 `TDataHnd___` 读为 UTF-8 字节。
   - 把字节解析为 JSON。
   - 提取命名参数。
   - **调用对应的 `internal_call_*` 函数**（这个调用已经写好；AI 不碰它）。
   - 把返回字符串写回输出 `TDataHnd___`。
   - 一个 `try/except` 信封，把任何异常转为 `{"error": "..."}`。
4. **`function internal_call_...` 的壳**——FPC/Delphi `{$IFDEF}` 分支、`TCompute.Sync` 包装，以及一个**必须由 AI 填充的函数体**。
5. **`RegisterTools` 中的工具 schema 注册**——工具的 `name`、`description`、`target_app`、`target_api`，以及 JSON `parameters` schema。

Bootstrap 脚本还写出 `RegisterAPIs`（3 个 `LF_RegisterCallEx` 调用）与 `Execute_And_Reg_all`（App 创建、端点连接、Beacon 握手）的完整注册脚手架。

### 8.3 AI 填什么

AI 每个工具只填一样东西：**`Do_Sync___`（FPC）或匿名过程（Delphi）里的函数体**。

**工具 1 — `Generate`**：

1. 表单空检查。
2. 校验 `Language` 参数（仅 `pascal` / `c`）。
3. 在组合框中选择语言。
4. 把源文本写入源编辑器。
5. 按顺序调用解析 / 规范化 / 生成按钮处理器。
6. 从 ListView 读取生成的文件列表。
7. 从模型 JSON 读取单元名。
8. 构造文件清单 JSON 并返回。

**工具 2 — `ListFiles`**：

1. 表单空检查。
2. 遍历 ListView。
3. 返回文件名。

**工具 3 — `GetFile`**：

1. 表单空检查。
2. 把 `FileName` 与 ListView 条目匹配。
3. 读取匹配条目 `SubItems[0]` 处的文件（UTF-8）。
4. 返回文本。

AI **从不**写：

- `TCompute.Sync` 包装。
- 回调信封。
- 异常处理。
- LingoFuse 注册代码。
- 工具 schema。

### 8.4 为什么用 UI 同步模式

关键设计决策：**AI 不写新的状态管理逻辑**。每个 MCP 工具体都委派给 GUI 表单。托管链是：

```
MCP 客户端
    ↓ 调用 CodeDeclToJsonAbi_Generate（LingoFuse Call）
Callback_CodeDeclToJsonAbi_Generate（cdecl，工作线程）
    ↓ 调用 internal_call_...
internal_call_CodeDeclToJsonAbi_Generate
    ↓ TCompute.Sync(Do_Sync___)
Do_Sync___（在主线程运行）
    ↓ 写 code_decl_to_abi_json_form.SourceCodeEditor.Text
    ↓ 调用 code_decl_to_abi_json_form.ParseSourceToJsonClick
    ↓ 调用 code_decl_to_abi_json_form.NormalizeJsonToModelClick
    ↓ 调用 code_decl_to_abi_json_form.GenerateAllSourcesClick
    ↓ 读 code_decl_to_abi_json_form.final_source_file_ListView
    ↓ 返回 TCompute.Sync
TCompute.Sync 返回
    ↓ internal_call_* 返回 JSON 字符串
Callback_* 把字符串写到输出 DataHandle
    ↓ LingoFuse 返回 MCP 客户端
```

那条链中的每一个箭头都是 **Bootstrap 脚本写一次的**，除了 `Do_Sync___` 内部每个工具所需的 UI 触碰。

**这种设计的后果**：

1. **GUI 是唯一真相源。** 没有并行状态。
2. **加一个新 MCP 工具是纯机械操作。** 复制一个 `internal_call_*` 对，重命名，指向不同的表单字段或按钮点击，把工具 schema 加到 `RegisterTools` 即可。
3. **GUI 的按钮点击处理器实际上就是 MCP 工具实现。** MCP 层只是一层薄薄的遥控。
4. **线程安全是继承来的，不是重新发明的。** `TCompute.Sync` 把函数体调到主线程。
5. **不新增状态字段。** 如果某个 MCP 工具需要一个值，那个值必须已经以表单编辑器或表单字段的形式存在。

### 8.5 为什么缩减为三个工具

上一轮迭代暴露了 24 个工具。那是一个**遥控面板**，不是智能体友好的 API。智能体必须理解：

- 24 个工具里哪 2 个是输入工具。
- 哪 1 个是生成工具。
- 剩余 21 个读取器里它需要哪几个。

这是一个**可发现性问题**：智能体的第一次动作总是错的，纠错需要一整轮重新生成。

三工具设计解决了它：

- **每个动词一个工具**：Generate、List、Get。
- **Generate** 一次产出**所有**目标。
- **List** / **Get** 是纯读取。

### 8.6 加一个新工具——机械配方

要加第四个工具：

1. **选择合适的模式**（setter、reader、driver、cache reader）。
2. **在 Bootstrap 脚本的工具表里**加一条，含：
   - 工具名。
   - 描述字符串。
   - 参数列表。
   - 模式标识。
3. **重跑 Bootstrap 脚本。** 它会重新生成单元，带上新回调、新桩、新工具 schema。
4. **按所选模式填入 AI 函数体**。
5. **如果工具需要新编辑器或新标签，更新 GUI。**
6. **重新编译 GUI 可执行文件。**

工具会自动出现在 Beacon 的工具列表中。其他文件无需改动。

### 8.7 AI 绝对不能做的事

- **不要为某个 MCP 工具往表单加新状态字段。**
- **不要从工作线程调用 UI 方法。** 每次 UI 触碰都必须在 `Do_Sync___` 里。
- **不要绕过回调信封。** 让异常向上传播；信封会把它转成 `{"error": "..."}`。
- **不要重命名或重编号工具。** 工具名是外部调用方依赖的稳定标识。
- **不要在不修改 AI 填充函数体的情况下修改工具 schema。**

---

## 第 9 章　程序化接口

工具也可以从另一个程序驱动。本章描述**公开 API 表面**——CLI、GUI 与 MCP 提供器内部调用的同一批函数。

### 9.1 API 所在位置

| 单元 | 导出 |
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
| （其他语言同理） | ... |

每个代码函数返回一个 `TPascalStringList`，调用方负责释放。**没有 `Generate*Readme` 函数——`.md` 生成功能已移除。**

### 9.2 Model 构建

生成器消费一个 `TPascal_Func_Model`。要从源文本构建一个：

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
        Model.Typ_Normalize_Func := tnf_ABI;   // ABI 生成器要求
        Model.LoadFromParser(Parser, Report);
        // Model 现在可交给生成器函数使用了。
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

对 C 头文件，换成 `CreateFrom_C_Code`。

### 9.3 最小可行嵌入

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
      Model.LoadFromParser(Parser, nil);      // nil report = 静默

      Code := GenerateHTTPServicePascalCode(Model);
      try
        if Code <> nil then
          Code.SaveToFile('MyUnit_http_json_service_unit.pas');
      finally
        Code.Free;
      end;

      // 若目标是 C++，还要产出 CMake 对：
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

**注意**：不再需要调用 `Generate*Readme`。`.md` 生成器已移除。

### 9.4 契约总结

| 函数族 | 输入 | 输出 | 说明 |
|--------|------|------|------|
| `Generate*Code` | `TPascal_Func_Model`（必须 `tnf_ABI`） | `TPascalStringList` 或 `nil` | 调用方释放；空 model 时为 `nil` |
| `GenerateCMakeScript` / `GenerateTestMainCpp` | `TPascal_Func_Model` | `TPascalStringList` 或 `nil` | 调用方释放；固定名输出文件 |
| `tpascal_func_decl_tool.CreateFrom_*` | 源文本 | parser 实例 | 调用方释放 |
| `TPascal_Func_Model.LoadFromParser` | parser + 可选 report | — | 应用类型家族过滤器 |

### 9.5 只产出单侧（服务或调用）

```pascal
// 只产出 Pascal 服务侧
Code := GenerateHTTPServicePascalCode(Model);

// 只产出 Pascal 调用侧
Code := GenerateHTTPCallPascalCode(Model);

// 只产出 Python 服务侧
Code := GenerateHTTPServicePythonCode(Model);

// 只产出 Rust 调用侧
Code := GenerateHTTPCallRustCode(Model);

// 只产出 Java 服务侧
Code := GenerateHTTPServiceJavaCode(Model);
```

**`Generate*Code` 函数不会自动产出测试程序或 CMake 脚本。** 如果要完整产物集，调用 `GenerateAllSourcesClick` 对应的逻辑（见 GUI 章节），或自己按需调用 `Generate*TestCode` / `GenerateCMakeScript` / `GenerateTestMainCpp`。

### 9.6 把自定义生成器注册进工具本身

如果你在扩展工具，并希望你的生成器出现在 CLI、GUI、MCP 前端里，你必须在三处注册：

1. `code_decl_to_json_abi.lpr` —— `uses` 子句，让单元的 `initialization` 运行。
2. `code_decl_to_abi_json_frm.pas` —— `implementation uses`，让 GUI 能调用。
3. `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas` —— 如果新增了工具，按第 8.6 章的机械配方加。

**大多数情况下，你只需要在前两处注册**；三工具 MCP 层会自动感知新的产物（通过 `final_source_file_ListView`）。

### 9.7 注册新的 CodeGenEntry

每个生成器单元在其 `initialization` 段调用 `RegisterCodeGenEntry`。**这个注册是工具链识别生成器的唯一方式。**

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

**新增一个目标语言时**，需要在其 generator 单元里补上 `RegisterCodeGenEntry` 调用。**`akServiceReadme` / `akCallReadme` / `akTestReadme` 这些 Kind 已不再被任何生成器注册**（`.md` 生成功能移除后它们成为死枚举值）。

---

## 第 10 章　产物清单

### 10.1 每个产物的用途

| 扩展名 / 名字 | 用途 | 运行期是否需要桥接程序 |
|---------------|------|:----------------------:|
| `*_http_json_service_unit.pas` | Pascal 服务：注册 API、监听 RPC、把 LingoFuse 调用转为 JSON。 | ❌（服务本身不走桥接程序） |
| `*_http_json_call_unit.pas` | Pascal 调用侧：把本地函数调用转为到 `bridge.py` 的 HTTP POST。 | ✅ **必需** |
| `*_http_json_service_main_test___.pas` | Pascal 服务侧测试驱动。 | ❌（本地测试） |
| `*_http_json_call_main_test___.pas` | Pascal 调用侧端到端测试驱动。 | ✅ **必需** |
| `*_http_json_service.py` | Python 服务。 | ❌ |
| `*_http_json_call.py` | Python 调用侧。 | ✅ **必需** |
| `*_http_json_service_main_test___.py` | Python 服务侧测试驱动。 | ❌ |
| `*_http_json_call_main_test___.py` | Python 调用侧端到端测试驱动。 | ✅ **必需** |
| `*_http_json_service.hpp` / `.cpp` | C++ 服务（`.hpp` 声明 + `.cpp` 实现）。 | ❌ |
| `*_http_json_call.hpp` / `.cpp` | C++ 调用侧。 | ✅ **必需** |
| `*_http_json_service.cs` | C# 服务模块。 | ❌ |
| `*_http_json_call.cs` | C# 调用侧。 | ✅ **必需** |
| `*_http_json_service_main_test___.cs` | C# 服务测试驱动。 | ❌（本地测试） |
| `*_http_json_call_main_test___.cs` | C# 调用测试驱动。 | ✅ **必需** |
| `*_http_json_call.js` | 浏览器 JS 客户端（IIFE，挂到 `window.<UnitName>Api`）。 | ✅ **必需** |
| `*_http_json_call_test.html` | 自包含 HTML 测试页；双击即可测试。 | ✅ **必需** |
| `*_http_json_service_node.js` | Node.js 服务模块。 | ❌ |
| `*_http_json_call_node.js` | Node.js 调用模块。 | ✅ **必需** |
| `*_http_json_service.ts` | TypeScript 服务模块。 | ❌ |
| `*_http_json_call_ts.ts` | TypeScript 调用模块。 | ✅ **必需** |
| `*_http_json_service_rs.rs` | Rust 服务模块。 | ❌ |
| `*_http_json_call_rs.rs` | Rust 调用模块。 | ✅ **必需** |
| `*_http_json_service_go.go` | Go 服务模块。 | ❌ |
| `*_http_json_call_go.go` | Go 调用模块。 | ✅ **必需** |
| `HttpJsonService.java` | Java 服务类。 | ❌ |
| `HttpJsonClient.java` | Java 调用类。 | ✅ **必需** |
| `*_http_json_service_swift.swift` | Swift 服务模块。 | ❌ |
| `*_http_json_call_swift.swift` | Swift 调用模块。 | ✅ **必需** |
| `*_http_json_service.rb` | Ruby 服务模块。 | ❌ |
| `*_http_json_call.rb` | Ruby 调用模块。 | ✅ **必需** |
| `*_http_json_service_zig.zig` | Zig 服务模块。 | ❌ |
| `*_http_json_call_zig.zig` | Zig 调用模块。 | ✅ **必需** |
| `*_http_json_service.erl` | Erlang 服务模块。 | ❌ |
| `*_http_json_call.erl` | Erlang 调用模块。 | ✅ **必需** |
| `*_http_json_service_mod.f90` | Fortran 服务模块。 | ❌ |
| `*_http_json_call_mod.f90` | Fortran 调用模块。 | ✅ **必需** |
| `*_http_json_service.jl` | Julia 服务模块。 | ❌ |
| `*_http_json_call.jl` | Julia 调用模块。 | ✅ **必需** |
| `*_http_json_service.R` | R 服务脚本。 | ❌ |
| `*_http_json_service_impl.R` | R 服务用户实现桩。 | ❌ |
| `*_http_json_call.R` | R 调用模块。 | ✅ **必需** |
| `*_http_json_call_delphi.pas` | Delphi 调用单元。 | ✅ **必需** |
| `*_http_json_call.dart` | Dart 调用模块。 | ✅ **必需** |
| `*_http_json_service.dart` | Dart 服务模块。 | ❌ |
| `*_http_json_call_php.php` | PHP 调用模块。 | ✅ **必需** |
| `CMakeLists.txt` | C++ 对 + C++ 测试驱动的 CMake 构建脚本。 | — |
| `test_main___.cpp` | CMake 脚本引用的 C++ 调用测试驱动。 | ✅ **必需**（执行时） |
| `launch_bridge.ps1` | 桥接程序启动脚本。 | — |
| `setup_js_tests.ps1` | Node.js 测试环境准备脚本。 | — |
| `setup_ts_tests.ps1` | TypeScript 测试环境准备脚本。 | — |
| `setup_zig_tests.ps1` | Zig 测试环境准备脚本。 | — |
| `setup_erlang_tests.ps1` | Erlang 测试环境准备脚本。 | — |
| `setup_fortran_tests.ps1` | Fortran 测试环境准备脚本。 | — |
| `setup_julia_tests.ps1` | Julia 测试环境准备脚本。 | — |
| `setup_r_tests.ps1` | R 测试环境准备脚本。 | — |

> **注意**：**没有 `*_readme.md` 产物。** 接口契约从代码本身、测试驱动、CMake 脚本、`setup_*_tests.ps1`、桩签名读。见第 3 章。
>
> **服务本身不走桥接程序。** 桥接程序只服务于 "调用 → 服务" 这一个方向。

### 10.2 文件位置

- **GUI / MCP**：产物写入可执行文件目录的 `<UnitName>/` 子目录。
- **CLI**：产物写入输出文件所在目录。

### 10.3 两份 CMake 产物是单元级的

`CMakeLists.txt` 与 `test_main___.cpp` 使用**固定名**（无单元前缀）。把两个不同的单元生成到同一目录会覆盖前一次的 CMake 文件。**一个目录一个单元。**

### 10.4 完整文件清单（五语言口径，20 份）

对于解析后名字为 `<U>` 的源单元：

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

**其他目标语言（Rust、Go、Java、Swift、Ruby、Zig、Erlang、Fortran、Julia、R、Dart、PHP、Node.js、TypeScript、Delphi）会产生各自的附加产物**，具体清单以 MCP `Generate` 的返回值或 GUI 的 "Final Source" 列表为准。

### 10.5 桥接程序是转发器，必须始终运行

**每个生成的调用侧（Pascal / Python / C++ / C# / JavaScript / Node.js / TypeScript / PHP / Rust / Go / Java / Delphi / Dart / Swift / Ruby / Zig / Erlang / Fortran / Julia / R）都通过桥接程序与后端通信：**

```
caller ──HTTP POST──▶ bridge.py / bridge.exe ──LF_Call──▶ service
caller ◀─HTTP resp──  bridge.py / bridge.exe ◀─LF ret───  service
```

**启动桥接程序时，要指定与服务一致的 endpoint，例如：**

```
python3 bridge.py --endpoint ipc:calc_http_json --port 8081 --no-precheck
```

**重要规则，再强调一次：**

- **桥接程序是转发器，必须始终运行。** 关掉桥接程序就等于关掉整条通路。
- 桥接程序可以是 `bridge.py`，也可以被编译成 `bridge.exe`——两者行为相同。
- 桥接程序应在**独立终端**中、前台运行。只有看到 HTTP 监听日志之后，才开始启动调用侧。
- 崩溃或被杀后，重启桥接程序即可恢复；调用侧不必重启。

### 10.6 CMake 脚本去哪里找 LingoFuse C++ 库

CMake 脚本要求一个目录，含：

- `LingoFuse.h`
- `LingoFuse.c`
- `LingoFuse.hpp`
- `lf_io.hpp`
- `lf_http_bridge_client.hpp`
- `json.hpp`

通过 `-DLINGOFUSE_CPP_LIB_DIR=/path/to/lf`，或在 cmake-gui 里填 **"LingoFuse C++ library directory"** 字段。

---

## 第 11 章　JSON 安全与稳定性

因为每个生成的调用侧最终都通过 HTTP 说 JSON，**JSON 就是整条流水线的安全与稳定边界**。以下各点由工具链保证：

### 11.1 UTF-8 贯穿始终

请求与响应始终是 UTF-8；桥接程序以 `ensure_ascii=False` 序列化，所以非 ASCII 负载（中文、emoji 及其他多字节内容）以字面 UTF-8 传输，而不是重新编码成 `\uXXXX` 转义。

### 11.2 NUL 终止符策略明确

LingoFuse 字符串在线上是 NUL 终止的。桥接程序在转发给 HTTP 客户端之前**剥离尾部 NUL**，生成的调用侧从不把多余的 NUL 混入 JSON。

### 11.3 桥接程序是二进制安全的

如果负载完全无法解析为 JSON，桥接程序会原样转发而不是损坏它。

### 11.4 确定性解包

桥接程序把每个服务响应包裹进稳定的信封（`{"status_code": ..., "headers": ..., "body": ...}`）。生成的调用侧解包 `body` 并检查 `body.code`；code `0` 返回 `body.result`，其他 code 抛出对应语言的异常。

### 11.5 线上不会静默丢精度

大整数默认以 JSON number 传输，对 Python 安全，对 C++（服务侧 `std::int64_t`）安全。**对 JavaScript 客户端不安全**，因为 JS `Number` 是 IEEE-754 double。对于打算给浏览器消费的 `int64` / `uint64` 接口，**推荐模式是让服务返回字符串**。

**受影响的调用侧产物**：

- JavaScript（`Number` 精度上限 2^53）
- PHP（整数溢出为 float）
- 浏览器端 HTML 测试页

**不受影响**：

- Pascal（Int64 完整）
- Python（任意精度整数）
- C++（`std::int64_t`）
- C#（`long`）
- Rust（`i64`）
- Go（`int64`）
- Java（`long`）
- Ruby（`Integer` 任意精度）
- R（`integer` 是 32 位，但 `numeric` 可承载 53 位精度）
- Julia（`Int64`）

### 11.6 稳定的错误 schema

每次失败都表现为以下之一：

- `{"error":"<message>"}`（工具级）
- `{"code": -N, "error": "<message>"}`（服务 / 桥接级）

调用侧把这些翻译成语言特定的异常：

| 语言 | 异常类 |
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
| Fortran | 通过 `ok` 输出参数 |
| Delphi | `EHTTPCallError` |

**实用结论**：只要桥接程序在运行、两侧端点字符串一致，**一种语言调用侧产生的 JSON 负载能被任何其他语言的服务侧正确消费，反之亦然**。

---

## 第 12 章　语言支持：今天与明天

### 12.1 强类型语言的优秀接口支持

对 **Pascal、C++、C#、Python、Rust、Go、Java、Swift、Ruby、Zig、Erlang、Fortran、Julia、R、Dart**，生成的接口是一等公民，而非仅仅桩：

- **Pascal**：生成的服务单元直接向 LingoFuse 注册 cdecl 回调，用 `Z.Json` 序列化。生成的调用单元用 `lf_http_bridge_client` 的 `LFHttpPost`，并把每个 API 暴露为**类型化自由函数**。
- **C++**：生成的服务产出干净的 `.hpp`/`.cpp` 对，带命名空间、类型化函数签名、`LF_CDECL` 兼容回调、JSON I/O 辅助。生成的调用侧为每个 API 暴露**类型化自由函数**，并携带一整套可调参数。**`CMakeLists.txt` 与 `test_main___.cpp` 与代码一同产出**。
- **C#**：生成的服务与调用模块使用官方 LingoFuse .NET 绑定。服务暴露 `Service.RegisterAPIs` 入口与每个例程的桩。调用侧为每个 API 暴露一个类型化同步函数与一个类型化异步函数。**两个测试程序一同产出**。
- **Python**：生成的服务模块暴露 `register_all_http_json_apis(app)` 入口与类型化内部桩；生成的调用模块为每个 API 暴露**一个类型化 Python 函数**，并有一个统一的内部 `_call_api()` 调度器。
- **Rust**：服务模块使用 `lingofuse` crate 注册回调；调用模块为每个 API 暴露一个同步函数（`ureq`）与一个异步函数（`reqwest` + `tokio`）。
- **Go**：服务模块使用 `lingofuse` Go 包；调用模块为每个 API 暴露一个同步函数与一个基于 channel 的异步函数。
- **Java**：服务模块使用 LingoFuse Java 包；调用模块为每个 API 暴露一个静态类型化方法。
- **Swift**：服务模块使用 `lingofuse` Swift 模块；调用模块为每个 API 暴露一个同步函数与一个 `async throws` 异步函数。
- **Ruby**：服务模块使用 `lingofuse` gem；调用模块为每个 API 暴露一个模块方法。
- **R**：服务模块使用 `lingofuse` + `jsonlite`；调用模块为每个 API 暴露一个函数（可选 `_async` 变体，基于 `future`）。
- **Julia**：服务模块使用 `LingoFuse` + `JSON3`；调用模块为每个 API 暴露一个同步函数与一个基于 `Task` 的异步函数。

**这些语言中的每一种**，三种类型家族（整数 / 浮点 / 字符串）都映射到该语言的天然原语，JSON 序列化在内部处理，开发者唯一要做的事就是填入 `internal_call_<Api>` 桩体。

### 12.2 全栈语言的优秀支持

- **JavaScript（浏览器）**：生成的 `.js` 是一个**自包含 IIFE**，挂到 `window.<Unit>Api`（或 `globalThis.<Unit>Api`），只使用 `fetch` / `Promise` / `async-await`，**零第三方依赖**。随附一份**自包含 HTML 测试页**。
- **TypeScript**：生成的 `.ts` 模块带类型化函数签名、`Promise<T>` 返回、可配置的 `HttpJsonCallOptions`。随附一份 TS 调用测试程序，需要 `tsx` 运行。
- **Node.js**：生成的 `.js` 是 `module.exports` 形式的 CommonJS 模块，使用 Node 18+ 内置 `fetch`。
- **PHP**：生成的 `.php` 使用 `curl_*`（首选）或 `fopen` + `stream_get_meta_data`，零第三方依赖。

### 12.3 系统为无上限扩展而设计

加一个新目标语言是一个**机械过程**，不是架构变更。步骤是：

1. 创建两个生成器单元：`<lang>_abi_service_generator_tool.pas` 与 `<lang>_abi_call_generator_tool.pas`。
2. 提供一张从三种 ABI 家族到目标语言原生类型的映射表。
3. 把新单元注册进主程序、CLI 分发器、GUI 表单。
4. 更新 CLI 的 `Detect_Target_Lang` 与帮助文本。
5. **不需要修改 MCP 层**——三工具 MCP 会自动感知新的产物（通过 `final_source_file_ListView`）。

**支持的语种数量没有架构上限。** 只要一种语言具备 (a) HTTP 客户端、(b) JSON 库、(c) 能说线上协议的运行时，它就是一个候选。

**加一种语言时，面向用户的契约不变**：同样的 CLI 标志、同样的 GUI 工作流、同样的三个 MCP 工具继续工作。

### 12.4 语言支持矩阵（详见附录 E）

完整的支持矩阵（每个语言的支持方向、扩展名、构建脚本、测试程序）见 **[附录 E — 语言支持矩阵](#附录-e语言支持矩阵)**。

---

## 第 13 章　常见问题解答

### 问题 1：为什么我传入的函数在生成结果里不见了？

检查三件事：

1. **函数是否顶层**（在 `interface` 段，而不是嵌套在 `class` / `record` 里）？嵌套声明会被跳过。
2. **参数与返回类型是否在支持集合里**？只有整数家族、浮点家族、字符串家族被接受。
3. **函数名是否非空**？

### 问题 2：为什么模型 JSON 里的函数比源文件少？

同问题 1。规范化期间，任何带不支持类型的函数会被整体丢弃。

### 问题 3：CLI 被要求输出 `.js` 但没给 `--call` 会怎样？

立刻以参数错误退出，退出码 `1`。JavaScript 是调用侧专属目标。

### 问题 4：CLI 跑完后完全看不到输出。

CLI 模式下，本工具把全部 `DoStatus` 消息写到 stdout。如果你从 IDE 里运行或重定向了 stdout，可能看不到。直接在终端里运行。

### 问题 5：GUI 里的"rule document"按钮点了没反应。

可执行文件目录缺少 `pascal_code_abi_rule.md` 或 `C_code_abi_rule.md`。把这两份文件放到可执行文件旁边。**这两份是工具自带的规则文件，与 `.md` 生成功能无关。**

### 问题 6：智能体调用返回 `{"error":"Form not available"}`。

GUI 没在运行。MCP 服务是 GUI 生命期服务；GUI 关闭后全部工具离线。

### 问题 7：智能体调用返回 `{"error":"Beacon not available ..."}`。

Beacon 服务（默认 `agent_main_app`）不在线，或它的端点与本工具的端点不一致。检查双方的 `--endpoint` 参数。

### 问题 8：`Language="python"` 会怎样？

返回 `{"error":"Unsupported language. Use ''pascal'' or ''c''."}`。

`"python"`、`"cpp"`、`"csharp"`、`"javascript"` 是**目标**语言。要产出 Python 服务，传 `"pascal"` 或 `"c"` 作为 `Language`，然后对清单里的 Python 命名文件调用 `GetFile`。

### 问题 9：多次调用 `Generate` 会污染结果吗？

不会。每次 `Generate` 从零重跑所有生成器，覆盖上一次的会话与磁盘内容。

### 问题 10：我可以只生成一种目标语言吗？

**不行。** `Generate` 一次产出所有目标。如果你只想要其中某几份，用 `GetFile` 从清单里挑；磁盘上的其他文件可以忽略。

### 问题 11：运行生成的调用侧或 HTML 测试页时报 `Network error` / `Failed to fetch` / `Connection refused`。

**99% 的情况是桥接程序没在运行（或曾经在运行、被关掉了）。**

排查步骤：

1. **确认桥接程序确实在运行**：检查它的终端有没有实时日志输出。
2. **确认桥接程序的端点与服务一致**。
3. **确认桥接程序的端口与调用侧预期一致**：默认 `8081`。
4. **重启桥接程序**。

> 再强调一次：**桥接程序（`bridge.py` / `bridge.exe`）是转发器，必须始终运行。**

### 问题 12：服务起来了——为什么我还是调不到？

服务、桥接程序、调用侧是**三个独立进程**，三者都需要：

```
服务进程（必须在线）
     ▲
     │ LF_Call
桥接程序进程（必须在线、前台、始终运行）
     ▲
     │ HTTP POST
调用侧进程（按需启动）
```

- 只有服务、没有桥接 → 调用侧报 `Network error`。
- 只有桥接、没有服务 → 桥接程序报 API 不可用 / 超时。
- 三者都在但启动顺序不对 → 按 "服务 → 桥接 → 调用" 重启。

### 问题 13：**没有 `.md` 怎么构建？**

**这是新版本最大的变化。** 接口契约从以下实体读：

- **桩签名**（`internal_call_<Api>`）→ API 名、参数类型、返回类型。
- **测试驱动**（`*_main_test___.*`）→ 调用示例。
- **CMakeLists.txt**（C++）→ 目标名、源文件、链接库。
- **setup_*_tests.ps1**（多语言）→ 环境准备步骤。
- **生成代码顶部注释块** → 依赖、线上协议、禁止事项。
- **生成代码常量声明** → 默认 Base URL / 超时 / 桥接 App 名。

**见第 3 章**。**本文档第 14 章（构建与部署实战）也给出了每种语言的完整步骤。**

### 问题 14：如何构建生成的 C++？

把 `.hpp`、`.cpp`、`CMakeLists.txt`、`test_main___.cpp` 放进一个目录，然后：

```bash
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

CMake 工程构建两个可执行文件：`<Unit>_http_json_service` 与 `<Unit>_http_json_call_test`。

### 问题 15：CMake 脚本会复制 LingoFuse DLL 吗？

不会。把 `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` 与 `z_ipc_*` 复制到可执行文件旁边，或把它们的目录加入 `PATH` / `LD_LIBRARY_PATH`。

### 问题 16：生成的 Pascal 的测试程序在哪里？

**在 `<Unit>_http_json_service_main_test___.pas` 和 `<Unit>_http_json_call_main_test___.pas` 里。** 它们就是完整的测试程序；直接 `fpc` 编译即可。

### 问题 17：如何构建生成的 Python 服务？

```bash
pip install requests
python3 <Unit>_http_json_service.py
```

**`if __name__ == "__main__":` 块会启动服务。**

### 问题 18：如何构建生成的 C# 服务？

```bash
dotnet new console -o my_service
cd my_service
cp ../<Unit>_http_json_service.cs .
cp ../<Unit>_http_json_service_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

调用侧换成 `<Unit>_http_json_call.cs` 与 `<Unit>_http_json_call_main_test___.cs`。

### 问题 19：MCP 工具提供器单元是怎么构建的？我必须手写吗？

不用。它由一个**三阶段构建**产出：

1. **Bootstrap 脚本**——产出结构完整的单元：回调、错误信封、工具 schema、LingoFuse 注册、函数壳。
2. **AI 填充**——用 UI 同步逻辑填充每个 `internal_call_*` 函数体。
3. **编译**——该单元被编进 GUI 可执行文件。

AI 的贡献是每个工具少量的 UI 触碰；其余全是机械的。

### 问题 20：为什么 MCP 工具数从 24 缩减到 3？

因为 24 个工具是一个**遥控面板**，不是智能体友好的 API。智能体的第一次动作总是错的，纠错需要一整轮重新生成。三工具设计给智能体每个动词一个工具：

- `Generate` —— 一次调用产出所有目标。
- `ListFiles` —— 看看产出了什么。
- `GetFile` —— 读你需要的内容。

智能体的第一次三工具工作流尝试就成功。这就是全部意义。

### 问题 21：**为什么不再生成 `.md`？**

因为 `.md` 生成会产生**过于庞大的文档体积**。多语言目标意味着每份 `.md` 都要为每种语言维护一套完整的构建命令、故障排查表、API 参考——体积膨胀到不可接受。

**移除 `.md` 后，接口契约仍可从生成代码、测试驱动、CMake 脚本、`setup_*_tests.ps1` 中获取**。这些是活的、始终与代码同步的产物。见第 3 章与第 14 章。

### 问题 22：`--lang` 参数有哪些可选值？

运行 `code_decl_to_json_abi --list-languages` 查看全部已注册的语言 id。常见值包括：

`pascal`、`python`、`cpp`、`csharp`、`javascript`、`nodejs`、`typescript`、`php`、`rust`、`go`、`java`、`delphi`、`dart`、`swift`、`ruby`、`zig`、`erlang`、`fortran`、`julia`、`r`。

### 问题 23：Rust 调用侧选同步还是异步？

两者都行，视场景而定：

- **同步（`ureq`）**：简单、无 async 运行时、适合脚本和 CLI 工具。
- **异步（`reqwest` + `tokio`）**：并发高、与 `tokio` 生态一致、适合服务端。

**两个变体都由生成器产出**，可以只用其中之一。

### 问题 24：Julia 为什么必须 `--threads=2`？

因为 Julia 的 LingoFuse 绑定需要至少两个线程才能工作：一个用于 `start_callback_consumer` 的回调消费，一个用于主线程的同步等待。`--threads=1` 会死锁。

### 问题 25：R 的 `*_async` 函数为什么必须是 `plan("sequential")`？

因为 `future` 的 `multisession` / `multicore` 计划会 fork worker 进程，而 LingoFuse 运行时在子进程中没有初始化，导致内部调用永远失败。生成的 `*_async` 函数会在 dispatch 时检查 `future::plan()`，若计划不兼容则立刻报错。**要并发就用同步函数 + 你自己的线程池**。

### 问题 26：生成的 R 服务如何优雅停止？

生成的 R 服务监听 `service.exit` 哨兵文件。**打开第二个 PowerShell 窗口**，运行：

```powershell
'' > "<脚本目录>\service.exit"
```

服务会在下一次轮询（约 100ms 内）检测到，按顺序执行 `exit_main_thread` → `free_app` → `shutdown`，然后退出。**Ctrl+C 是备选方案**，但某些平台可能留下终端状态异常。

### 问题 27：生成的 Zig 服务如何处理 Ctrl+C？

Zig 生成的服务在 `main` 中 `readLine()` 等待回车，回车后执行 `exitMainThread` → `app.deinit()` → `shutdown()`。**Ctrl+C 由操作系统直接终止进程，LingoFuse 清理由 OS 完成**，不需要用户额外处理。

### 问题 28：生成的 Erlang 服务的 `run_smoke_test/0` 和 `main/0` 有什么区别？

- **`main/0`**：启动完整的 LingoFuse mesh（`prepare_service` + `prepare_client`），开始监听，进入事件循环。需要 `bridge.py` 在运行。
- **`run_smoke_test/0`**：**不**启动 mesh，只在进程内创建 `AppHandle`，通过 `lingofuse:local_call/2` 直接调用每个 API。**不需要 `bridge.py`**。

### 问题 29：生成的 Fortran 代码如何处理 NUL 终止符？

LingoFuse 字符串是 NUL 终止的。生成的 Fortran 调用侧在读取响应后，用 `strip_trailing_nul` 辅助函数剥掉尾部 NUL，再交给 JSON 解析。

### 问题 30：生成的 Julia 服务的 `main/0` 和 `run_smoke_test` 有什么区别？

- **`main/0`**（生成的模块）：完整启动 LingoFuse mesh，阻塞直到 SIGINT。
- **`run_smoke_test`**（测试程序里的 `run_smoke()`）：在进程内创建 `AppHandle`，通过 `local_call` 直接调用每个 API。**不需要 `bridge.py`**。

### 问题 31：生成代码里那堆 `LF_CDECL` / `LF_CDECL_FUNC` 是什么？

`LF_CDECL` 是 LingoFuse C ABI 提供的**调用约定宏**。它在不同平台上展开为 `__cdecl`（MSVC）或 `__attribute__((cdecl))`（MinGW / clang-cl / GCC）。**生成的 C++ 服务代码用它声明回调**，这样回调在 C ABI 上能被 LingoFuse 正确调用。

**不要重定义它。** 如果需要在非 LingoFuse 代码里使用，`#include "LingoFuse.h"` 即可获得定义。

### 问题 32：生成代码里为什么会看到 `_SyncResultBox` / `@unchecked Sendable` / `@unchecked Sendable` 这种字样？

这是 **Swift 生成器**为同步调用路径准备的线程安全包装。`DispatchSemaphore.wait()` / `.signal()` 建立了 happens-before 关系，Swift 并发检查器无法跨 C 回调边界推断这个关系，所以显式标注 `@unchecked Sendable`。**这是正确且必要的**，不是 hack。

### 问题 33：Rust 生成器里 `ureq::Error::Status(200, response)` 分支怎么处理？

那是 `ureq` 在 4xx / 5xx 时返回的 `Status` 变体。生成的代码在这里读取响应体并交给 `parse_envelope` 统一处理。`parse_envelope` 会检查 HTTP 状态码并正确构造 `HttpCallError`。

### 问题 34：`int64` 在 JavaScript 客户端为什么会丢精度？

JS `Number` 是 IEEE-754 double，53 位尾数。`2^53 + 1` 不等于 `2^53 + 1`，会静默四舍五入。**解决方案**：让服务侧把 `int64` / `uint64` 返回为字符串，客户端用 bignum 库解析。

### 问题 35：`HttpJsonCallError` 和 `LFHttpCallError` 有什么区别？

- **`HttpJsonCallError`**：TypeScript / PHP / Java（`HTTPCallException`）等其他语言的异常类名。
- **`LFHttpCallError`**：浏览器 JavaScript 的异常类名（带 `LF` 前缀，因为 JS 全局作用域里避免命名冲突）。

**两者语义完全一致**：`.code` / `.httpStatus` / `.message`。

---

## 第 14 章　构建与部署实战

本章是 `.md` 移除后最重要的补充章节。它按语言给出**从产物到可运行程序**的完整步骤。

### 14.1 Pascal

#### 14.1.1 依赖

- FPC 3.2+ 或 Delphi 11+。
- `lingofuse_import.pas`（LingoFuse Pascal 绑定）。
- `Z.Core`、`Z.PascalStrings`、`Z.UPascalStrings`、`Z.Json`、`Z.UnicodeMixedLib`。

#### 14.1.2 构建服务侧

```bash
fpc -Fu<path-to-ZNetV2/ZCore> -Fu<path-to-ZNetV2> \
    -Fu<path-to-generated-directory> \
    <Unit>_http_json_service_main_test___.pas
```

或者把生成的单元 `uses` 进你自己的 `.lpr`：

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

#### 14.1.3 构建调用侧

```bash
fpc -Fu<path-to-ZNetV2/ZCore> -Fu<path-to-ZNetV2> \
    -Fu<path-to-generated-directory> \
    <Unit>_http_json_call_main_test___.pas
```

#### 14.1.4 部署清单

- `LingoFuse64.dll`（或 `liblingofuse.so` / `liblingofuse.dylib`）
- `z_ipc_64.dll`（或 `libz_ipc_64.so`）
- 生成的 `.pas` 或 `.ppu` 文件

### 14.2 Python

#### 14.2.1 依赖

```bash
pip install requests
```

**服务侧**还需要 `lingofuse` Python 包（从 LingoFuse 发行版安装）：

```bash
pip install <path-to-LingoFuse>/python
```

#### 14.2.2 运行服务侧

```bash
python3 <Unit>_http_json_service.py
```

#### 14.2.3 运行调用侧

```bash
python3 <Unit>_http_json_call_main_test___.py
```

**覆盖 Base URL**：

```bash
python3 <Unit>_http_json_call_main_test___.py http://10.0.0.5:8081/<Unit>
```

#### 14.2.4 部署清单

- `LingoFuse64.dll`（服务侧）
- `z_ipc_64.dll`
- 生成的 `.py` 文件
- `PYTHONPATH` 指向 LingoFuse Python 包（服务侧）

### 14.3 C++

#### 14.3.1 依赖

- CMake 3.15+
- C 与 C++ 编译器（MSVC / g++ / clang++）
- LingoFuse C++ 发行目录

#### 14.3.2 构建

```bash
# 确保 <Unit>_http_json_service.hpp/.cpp、<Unit>_http_json_call.hpp/.cpp、
# CMakeLists.txt、test_main___.cpp 都在同一目录。
cd <that-directory>

cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=/path/to/lf
cmake --build build
```

**Windows + MSVC**：

```cmd
cmake -S . -B build -DLINGOFUSE_CPP_LIB_DIR=C:\LingoFuse\cpp -G "Visual Studio 17 2022"
cmake --build build --config Release
```

#### 14.3.3 部署清单

- `LingoFuse64.dll`（或 `.so` / `.dylib`）
- `z_ipc_64.dll`
- 两个可执行文件：`<Unit>_http_json_service`、`<Unit>_http_json_call_test`

**DLL 复制**：CMake 脚本**不**复制运行时 DLL。手动复制或设置 `PATH` / `LD_LIBRARY_PATH`。

### 14.4 C#

#### 14.4.1 依赖

- .NET 8.0+
- LingoFuse .NET 绑定（`LingoFuse.dll`）
- LingoFuse 原生库

#### 14.4.2 构建服务侧

```bash
dotnet new console -o my_service
cd my_service
cp ../<Unit>_http_json_service.cs .
cp ../<Unit>_http_json_service_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

#### 14.4.3 构建调用侧

```bash
dotnet new console -o my_call
cd my_call
cp ../<Unit>_http_json_call.cs .
cp ../<Unit>_http_json_call_main_test___.cs Program.cs
dotnet add reference ../LingoFuse/LingoFuse.csproj
cp ../LingoFuse64.dll .
dotnet run
```

#### 14.4.4 部署清单

- `LingoFuse64.dll`（或 `.so` / `.dylib`）
- `z_ipc_64.dll`
- `LingoFuse.dll`（.NET 绑定）
- 生成的 `.cs` 文件

### 14.5 JavaScript（浏览器）

#### 14.5.1 依赖

无。浏览器内置 `fetch`。

#### 14.5.2 使用

**方式 A：双击 `*_test.html`**

直接打开测试页。

**方式 B：在你自己页面里引入**

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

**方式 C：通过 HTTP 服务提供**

```bash
python3 -m http.server 9000
# 打开 http://127.0.0.1:9000/<Unit>_http_json_call_test.html
```

#### 14.5.3 CORS

桥接程序需要返回 `Access-Control-Allow-Origin: *`（或具体 origin）。`bridge.py` 默认开启 CORS；如果没开，在桥接启动参数里加 `--cors '*'`。

#### 14.5.4 部署清单

- `LingoFuse64.dll`（服务侧）
- `z_ipc_64.dll`
- 生成的 `.js` 与 `.html`

### 14.6 Node.js

#### 14.6.1 依赖

```bash
npm install lingofuse-js
```

或用生成的 `setup_js_tests.ps1`。

#### 14.6.2 运行

**服务侧**：

```bash
node <Unit>_http_json_service_node.js
```

**调用侧**：

```bash
node <Unit>_http_json_call_main_test___.js
```

**覆盖 Base URL**：

```bash
node <Unit>_http_json_call_main_test___.js http://10.0.0.5:8081/<Unit>
```

### 14.7 TypeScript

#### 14.7.1 依赖

```bash
npm install lingofuse-ts tsx
```

或用生成的 `setup_ts_tests.ps1`。

#### 14.7.2 运行

**服务侧**：

```bash
./node_modules/.bin/tsx.cmd <Unit>_http_json_service.ts
```

**调用侧**：

```bash
./node_modules/.bin/tsx.cmd <Unit>_http_json_call_main_test___.ts
```

### 14.8 PHP

#### 14.8.1 依赖

`curl_*`（首选）或 `fopen`。PHP 7.4+。

#### 14.8.2 运行调用侧

```bash
php <Unit>_http_json_call_main_test___.php
```

**覆盖 Base URL**：

```bash
php <Unit>_http_json_call_main_test___.php http://10.0.0.5:8081/<Unit>
```

### 14.9 Rust

#### 14.9.1 依赖

**`Cargo.toml`**（调用侧）：

```toml
[dependencies]
ureq = "2"
reqwest = { version = "0.12", features = ["json"] }
tokio = { version = "1", features = ["rt", "rt-multi-thread", "macros"] }
serde_json = "1"
```

**`Cargo.toml`**（服务侧）：

```toml
[dependencies]
lingofuse = { path = "../LingoFuse/rust" }
serde_json = "1"
```

#### 14.9.2 运行

**服务侧**：

```bash
cargo new my_service
cd my_service
cp ../<Unit>_http_json_service_rs.rs src/main.rs
cargo run
```

**调用侧**：

```bash
cargo new my_call
cd my_call
cp ../<Unit>_http_json_call_rs.rs src/main.rs
cp ../<Unit>_http_json_call_main_test___.rs src/main.rs
cargo run
```

#### 14.9.3 部署清单

- `LingoFuse64.dll`（或 `.so` / `.dylib`）
- `z_ipc_64.dll`

### 14.10 Go

#### 14.10.1 依赖

```bash
go mod init calculator
go get github.com/PassByYou888/LingoFuse/go
```

#### 14.10.2 运行

**服务侧**：

```bash
cp ../<Unit>_http_json_service_go.go .
cp ../<Unit>_http_json_service_main_test.go .
go test -v
# 或
go build -o service .
./service
```

**调用侧**：

```bash
cp ../<Unit>_http_json_call_go.go .
cp ../<Unit>_http_json_call_main_test.go .
go test -v
```

### 14.11 Java

#### 14.11.1 依赖

- JDK 11+
- `jackson-databind.jar`
- `lingofuse.jar`（服务侧）

#### 14.11.2 运行

**服务侧**：

```bash
javac -cp lingofuse.jar:jackson-databind.jar *.java
java --enable-native-access=ALL-UNNAMED \
     -cp .:lingofuse.jar:jackson-databind.jar \
     HttpJsonService
```

**调用侧**：

```bash
javac -cp jackson-databind.jar HttpJsonClient.java HttpJsonCallTest.java
java -cp .:jackson-databind.jar HttpJsonCallTest
```

### 14.12 Delphi

#### 14.12.1 依赖

Delphi 10.3+。`System.Net.HttpClient`、`System.JSON`。

#### 14.12.2 编译

```cmd
dcc32 <Unit>_http_json_call_delphi_test___.dpr
```

或在 IDE 中打开 `.dpr` 编译。

#### 14.12.3 运行

```cmd
<Unit>_http_json_call_delphi_test___.exe
```

### 14.13 Dart

#### 14.13.1 依赖

`pubspec.yaml` 加：

```yaml
dependencies:
  http: ^1.0.0
```

#### 14.13.2 运行

**调用侧**：

```bash
dart run <Unit>_http_json_call_main_test___.dart
```

**覆盖 Base URL**：

```bash
dart run <Unit>_http_json_call_main_test___.dart http://10.0.0.5:8081/<Unit>
```

### 14.14 Swift

#### 14.14.1 依赖

- Swift 5.9+
- macOS 12+ / iOS 15+（异步 API 需要）

#### 14.14.2 运行

**调用侧**：

```bash
swift <Unit>_http_json_call_main_test___.swift
```

**Windows / Linux**：Swift for Windows / Swift on Linux。

### 14.15 Ruby

#### 14.15.1 依赖

**服务侧**：

```bash
gem install lingofuse
```

**调用侧**：仅标准库。

#### 14.15.2 运行

**服务侧**：

```bash
ruby <Unit>_http_json_service.rb
```

**调用侧**：

```bash
ruby <Unit>_http_json_call_main_test___.rb
```

**覆盖 Base URL**：

```bash
ruby <Unit>_http_json_call_main_test___.rb http://10.0.0.5:8081/<Unit>
```

### 14.16 Zig

#### 14.16.1 依赖

- Zig 0.13+
- `lingofuse` Zig 绑定

#### 14.16.2 运行

**用生成的 `setup_zig_tests.ps1`**：

```powershell
.\setup_zig_tests.ps1 -ZigLibDir D:\LingoFuse\zig -BinaryDir D:\LingoFuse\Binary
```

脚本会创建 `zig_service_test/` 与 `zig_call_test/` 两个工程。

**手动**：

```bash
cd zig_service_test
zig build run
```

### 14.17 Erlang

#### 14.17.1 依赖

- Erlang/OTP 25+
- `lingofuse` Erlang binding

#### 14.17.2 运行

**用生成的 `setup_erlang_tests.ps1`**：

```powershell
.\setup_erlang_tests.ps1 -ErlangBindingDir D:\LingoFuse\erlang -RunSmoke
```

**手动**：

```bash
erlc -o ebin <Unit>_http_json_service.erl
escript <Unit>_http_json_service_main_test___.escript
```

### 14.18 Fortran

#### 14.18.1 依赖

- gfortran 9+
- `lf_fortran_mod.f90` + `lf_fortran.cpp`

#### 14.18.2 运行

**用生成的 `setup_fortran_tests.ps1`**：

```powershell
.\setup_fortran_tests.ps1 -FortranLibDir D:\LingoFuse\fortran\c_ext -RunSmoke
```

### 14.19 Julia

#### 14.19.1 依赖

- Julia 1.9+
- `LingoFuse`、`JSON3` 包
- 必须 `--threads=2`

#### 14.19.2 运行

**用生成的 `setup_julia_tests.ps1`**：

```powershell
.\setup_julia_tests.ps1 -JuliaBindingDir D:\LingoFuse\julia -RunSmoke
```

**手动**：

```bash
julia --project=<GenDir> --threads=2 <Unit>_http_json_service_main_test___.jl
```

### 14.20 R

#### 14.20.1 依赖

- R 4.0+
- `lingofuse`、`jsonlite`、`httr`、`future` 四个包

#### 14.20.2 运行

**用生成的 `setup_r_tests.ps1`**：

```powershell
.\setup_r_tests.ps1 -RLibDir D:\LingoFuse\r\lingofuse -InstallMissing -RunSmoke
```

**手动**：

```bash
Rscript <Unit>_http_json_service.R
Rscript <Unit>_http_json_call_main_test___.R
```

---

## 第 15 章　典型工作流完整走查

本章用一个具体例子走查从源文本到运行测试的完整流程。

### 15.1 输入源文本

`Calculator.pas`：

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

### 15.2 GUI 走查

1. **启动**：双击 `code_decl_to_json_abi.exe`（无参数）。
2. **页 1 Welcome**：点 "Next: Enter source code"。
3. **页 2 Source Code**：粘贴 `Calculator.pas` 的内容；点 "Select Language" 自动检测；点 "Next: Pascal/C → JSON"。
4. **页 3 Source ↔ JSON**：检查 LV0 JSON 是否包含 `Add` 与 `Sub`；点 "Next: JSON ↔ Model"。
5. **页 4 JSON ↔ Model**：检查 LV1 Model 是否包含两个函数；点 "Next: generate source"。
6. **页 5 Final Source**：浏览每个子标签；确认文件已写入 `<exe>/Calculator/` 目录。

**产物目录**：

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

### 15.3 从产物读契约

**打开 `Calculator_http_json_service_unit.pas`**：

```pascal
function internal_call_Add_Add(a: Int64; b: Int64): Int64;
```

→ **API 名**：`Add`；**参数**：`a: Int64`、`b: Int64`；**返回**：`Int64`。

**打开 `Calculator_http_json_call_unit.pas`**：

```pascal
var
  HTTP_CALL_BASE_URL: string = 'http://127.0.0.1:8081/Calculator';
  HTTP_CALL_TIMEOUT_MS: Integer = 30000;
```

→ **默认 Base URL**：`http://127.0.0.1:8081/Calculator`；**默认超时**：30000ms。

**打开 `Calculator_http_json_call_main_test___.pas`**：

```pascal
Test_Add_Sync;
Test_Add_Async;
```

→ **调用示例**：`Test_Add_Sync;` / `Test_Add_Async;`。

### 15.4 编译与运行

**终端 1（服务）**：

```bash
cd <exe>/Calculator
fpc -Fu<path-to-ZNetV2/ZCore> -Fu<path-to-ZNetV2> \
    Calculator_http_json_service_main_test___.pas
./Calculator_http_json_service_main_test___
```

**终端 2（桥接）**：

```bash
python3 bridge.py --endpoint ipc:Calculator_http_json --port 8081 --no-precheck
```

**终端 3（调用）**：

```bash
cd <exe>/Calculator
fpc -Fu<path-to-ZNetV2/ZCore> -Fu<path-to-ZNetV2> \
    Calculator_http_json_call_main_test___.pas
./Calculator_http_json_call_main_test___
```

**预期输出**：

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

### 15.5 CLI 走查

**生成服务侧**：

```bash
code_decl_to_json_abi Calculator.pas calculator_service.pas
```

**生成调用侧**：

```bash
code_decl_to_json_abi --call Calculator.pas calculator_call.pas
```

**编译与运行**（同 §15.4）。

### 15.6 MCP 走查

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

// 3. GetFile（读契约）
{ "tool": "CodeDeclToJsonAbi_GetFile",
  "arguments": { "FileName": "Calculator_http_json_service_unit.pas" } }
// → 读桩签名，得到 API 名与类型

{ "tool": "CodeDeclToJsonAbi_GetFile",
  "arguments": { "FileName": "Calculator_http_json_call_main_test___.pas" } }
// → 读调用示例
```

**注意**：**没有 `_readme.md` 要拉。** 契约全部从代码读。

---

## 附录 A — 一次运行的产物清单

### A.1 五语言口径（20 份）

见 §10.4。

### A.2 全语言口径

如果模型触发了全部已注册的语言，产物会是：

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

**共 90+ 份。没有一份是 `_readme.md`。**

**真实清单以 MCP `Generate` 的返回值或 GUI 的 "Final Source" 列表为准。**

---

## 附录 B — 错误码与异常类型速查表

### B.1 线上错误码

| 码 | 含义 | 典型 HTTP 状态 |
|:-:|------|:--------------:|
| `0` | 成功。绝不作为错误上报。 | 200 |
| `-1` | 远程调用失败（服务侧异常、网络失败、超时）。 | 200 或 0 |
| `-2` | 请求形状错误（畸形 URL 路径、无法序列化的请求体）。 | 400 |
| `-3` | 桥接程序预检查失败（桥接本地缓存尚未看到该 API）。 | 200 |
| `-4` | 桥接协议错误（畸形信封、缺字段）。 | 200 |

### B.2 工具级错误 JSON

| 工具 | 成功 | 失败 |
|------|------|------|
| `Generate` | `{"status":"ok","unit_name":"...","count":N,"files":[...]}` | `{"error":"<message>"}` |
| `ListFiles` | `{"status":"ok","count":N,"files":[...]}` | `{"status":"error",...}` |
| `GetFile` | `{"status":"ok","name":"...","text":"..."}` | `{"status":"error","name":"...","error":"..."}` |

### B.3 各语言异常类

见 §11.6。

### B.4 常见错误消息对照

| 消息 | 来源 |
|------|------|
| `Unsupported language. Use pascal or c.` | MCP `Generate` |
| `Form not available` | 三个 MCP 工具（GUI 未运行） |
| `File not found. Call ListFiles first to get valid names.` | MCP `GetFile` |
| `Generation failed: <reason>` | MCP `Generate` |
| `LF_PrepareClient returned -1` | LingoFuse 启动失败 |
| `LF_PrepareDone returned 0` | LingoFuse 启动（已在同一进程调用过） |
| `no found app("<name>")` | LingoFuse 路由失败 |
| `3029 function header doesn't match` | FPC 重载冲突 |
| `Illegal expression` / `Syntax error, ";" expected` | FPC 内联变量误用 |
| `Cannot determine link language` | CMake，`project()` 只声明 `CXX` |
| `dynamic constant assignment` | Ruby 对常量赋值 |
| `@unchecked Sendable` 警告 | Swift 并发检查（这是正确标注，不是 bug） |
| `PyImportError` / `ModuleNotFoundError` | 缺少 `requests` / `lingofuse` |
| `cargo: no such command: add` | Rust 版本过旧，用 `cargo add` 升级 |
| `go: module github.com/PassByYou888/LingoFuse not found` | 未 `go get` |
| `ClassNotFoundException: lingofuse.AppHandle` | `lingofuse.jar` 未加入 classpath |

---

## 附录 C — 命令行参数速查表

| 参数 | 简写 | 说明 |
|------|:----:|------|
| `--help` | `-h` / `-?` / `/?` | 打印帮助并退出 |
| `--list-languages` | `-ll` | 列出全部已注册的目标语言 |
| `--call` | `-c` | 生成调用侧（默认服务侧） |
| `--lang <id>` | `-l <id>` | 强制目标语言 |
| `<input_file>` | — | 输入源文件 |
| `<output_file>` | — | 输出文件 / 目录 |

### C.1 输入扩展名 → 源语言

| 扩展名 | 源语言 |
|--------|--------|
| `.pas` / `.pp` / `.p` | Pascal |
| `.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx` | C |

### C.2 输出扩展名 → 目标语言

见 §6.4。

### C.3 退出码

| 码 | 含义 |
|:-:|------|
| `0` | 成功 |
| `1` | 缺少或非法参数 |
| `2` | 源解析失败 |
| `3` | 代码生成失败 |
| `4` | 文件 I/O 错误 |

---

## 附录 D — MCP 工具参数速查表

### D.1 `CodeDeclToJsonAbi_Generate`

| 参数 | 类型 | 必填 | 说明 |
|------|------|:----:|------|
| `Source` | string | ✅ | 完整源文本 |
| `Language` | string | ✅ | `"pascal"` 或 `"c"`，大小写不敏感 |

### D.2 `CodeDeclToJsonAbi_ListFiles`

无参数。

### D.3 `CodeDeclToJsonAbi_GetFile`

| 参数 | 类型 | 必填 | 说明 |
|------|------|:----:|------|
| `FileName` | string | ✅ | 必须是之前 `ListFiles` 返回过的值，大小写敏感 |

---

## 附录 E — 语言支持矩阵

| # | 语言 | 服务 | 调用 | 测试 | 构建脚本 | 依赖 | 特殊要求 |
|:-:|------|:----:|:----:|:----:|:--------:|------|----------|
| 1 | Pascal | ✅ | ✅ | ✅ | — | `lingofuse_import`、`Z.Core` | FPC 3.2+ 或 Delphi 11+ |
| 2 | Python | ✅ | ✅ | ✅ | — | `requests` | Python 3.8+ |
| 3 | C++ | ✅ | ✅ | ✅ | ✅ | `LingoFuse.hpp`、`lf_http_bridge_client.hpp`、`json.hpp` | C++17、CMake 3.15+ |
| 4 | C# | ✅ | ✅ | ✅ | — | LingoFuse .NET 绑定 | .NET 8.0+ |
| 5 | JavaScript | ❌ | ✅ | ✅ | — | 无（浏览器 `fetch`） | 现代浏览器 |
| 6 | Node.js | ✅ | ✅ | ✅ | ✅ | `lingofuse-js` | Node 18+ |
| 7 | TypeScript | ✅ | ✅ | ✅ | ✅ | `lingofuse-ts`、`tsx` | TS 5.0+、Node 18+ |
| 8 | PHP | ❌ | ✅ | ✅ | — | `curl_*` 或 `fopen` | PHP 7.4+ |
| 9 | Rust | ✅ | ✅ | ✅ | — | `lingofuse`、`ureq`、`reqwest`、`tokio`、`serde_json` | Rust 1.70+ |
| 10 | Go | ✅ | ✅ | ✅ | — | `lingofuse` Go 包 | Go 1.21+ |
| 11 | Java | ✅ | ✅ | ✅ | — | `lingofuse` Java 包、Jackson | JDK 11+ |
| 12 | Delphi | ❌ | ✅ | ✅ | — | `System.Net.HttpClient` | Delphi 10.3+ |
| 13 | Dart | ✅ | ✅ | ✅ | — | `http` 包 | Dart 3.0+ |
| 14 | Swift | ✅ | ✅ | ✅ | — | Foundation | Swift 5.9+ / macOS 12+ |
| 15 | Ruby | ✅ | ✅ | ✅ | — | `lingofuse` gem | Ruby 2.7+ / 3.0+ |
| 16 | Zig | ✅ | ✅ | ✅ | ✅ | `lingofuse` Zig 绑定 | Zig 0.13+ |
| 17 | Erlang | ✅ | ✅ | ✅ | ✅ | `lingofuse` Erlang 绑定、`httpc` | OTP 25+ |
| 18 | Fortran | ✅ | ✅ | ✅ | ✅ | `lf_fortran_mod.f90`、`lf_fortran.cpp` | gfortran 9+ |
| 19 | Julia | ✅ | ✅ | ✅ | ✅ | `LingoFuse`、`JSON3` | Julia 1.9+、`--threads=2` |
| 20 | R | ✅ | ✅ | ✅ | ✅ | `lingofuse`、`jsonlite`、`httr`、`future` | R 4.0+ |
| 21 | Bridge 启动 | — | — | — | ✅ | `bridge.py` | PowerShell 5.1+ |

**说明**：

- "✅" 表示该方向/产物已注册并且有生成器。
- "❌" 表示该方向/产物无生成器。
- "特殊要求" 列只列**用户必须知道的硬性前提**，不列完整依赖树。

---

## 附录 F — 接口契约获取入口对照表

| 契约类型 | 权威来源 | 文件示例 |
|----------|----------|----------|
| **API 名** | 注册表 | `<U>_http_json_service_unit.pas` 里的 `LF_RegisterCallEx` 调用 |
| **参数类型与个数** | 桩签名 | `internal_call_Add(a: Int64; b: Int64)` |
| **返回类型** | 桩签名 | `): Int64;` |
| **线上请求形状** | 固定协议 | `{ "args": [v1, v2, ...] }`（见第 10 章） |
| **线上响应形状** | 固定协议 | `{ "code": 0, "result": ... }` / `{ "code": -1, "error": ... }` |
| **调用示例** | 测试驱动 | `<U>_http_json_call_main_test___.pas` |
| **构建命令** | CMake 脚本 / `setup_*_tests.ps1` / 第 14 章 | `CMakeLists.txt`、`setup_js_tests.ps1` |
| **默认 Base URL** | 代码常量声明 | `HTTP_CALL_BASE_URL` / `DEFAULT_BASE_URL` |
| **默认超时** | 代码常量声明 | `HTTP_CALL_TIMEOUT_MS` / `DEFAULT_TIMEOUT_SECS` |
| **桥接 App 名** | 代码常量声明 | `__lf_http_bridge__`（各语言默认值一致） |
| **桥接 API 名** | 代码常量声明 | `__lf_outbound_post__`（各语言默认值一致） |
| **服务端点名** | 代码常量声明 | `HTTP_SERVICE_ENDPOINT` / `ENDPOINT` |
| **环境变量** | 生成代码顶部注释块 | `LINGOFUSE_DEBUG`、`PYTHONPATH` 等 |
| **线上协议** | 生成代码顶部注释块 | "request = { args: [...] }" / "response = { code, result }" |
| **禁止事项** | 生成代码顶部注释块 | "不要重定义 LF_CDECL" / "必须 init/deinit" |

---

## 附录 G — 各目标语言的产物文件后缀速查

| 语言 | 服务产物后缀 | 调用产物后缀 | 测试产物后缀 | 构建脚本 |
|------|-------------|-------------|-------------|----------|
| Pascal | `_http_json_service_unit.pas` | `_http_json_call_unit.pas` | `_http_json_service_main_test___.pas` / `_http_json_call_main_test___.pas` | — |
| Python | `_http_json_service.py` | `_http_json_call.py` | `_http_json_service_main_test___.py` / `_http_json_call_main_test___.py` | — |
| C++ | `_http_json_service.hpp` + `_http_json_service.cpp` | `_http_json_call.hpp` + `_http_json_call.cpp` | `test_main___.cpp` | `CMakeLists.txt` |
| C# | `_http_json_service.cs` | `_http_json_call.cs` | `_http_json_service_main_test___.cs` / `_http_json_call_main_test___.cs` | — |
| JavaScript | （不支持） | `_http_json_call.js` | `_http_json_call_test.html` | — |
| Node.js | `_http_json_service_node.js` | `_http_json_call_node.js` | `_http_json_service_main_test___.js` / `_http_json_call_main_test___.js` | `setup_js_tests.ps1` |
| TypeScript | `_http_json_service.ts` | `_http_json_call_ts.ts` | `_http_json_service_main_test___.ts` / `_http_json_call_main_test___.ts` | `setup_ts_tests.ps1` |
| PHP | （不支持） | `_http_json_call_php.php` | `_http_json_call_main_test___.php` | — |
| Rust | `_http_json_service_rs.rs` | `_http_json_call_rs.rs` | `_http_json_service_main_test___.rs` / `_http_json_call_main_test___.rs` | — |
| Go | `_http_json_service_go.go` | `_http_json_call_go.go` | `_http_json_service_main_test.go` / `_http_json_call_main_test.go` | — |
| Java | `HttpJsonService.java` | `HttpJsonClient.java` | `HttpJsonServiceTest.java` / `HttpJsonCallTest.java` | — |
| Delphi | （不支持） | `_http_json_call_delphi.pas` | `_http_json_call_delphi_test___.dpr` | — |
| Dart | `_http_json_service.dart` | `_http_json_call.dart` | `_http_json_service_main_test___.dart` / `_http_json_call_main_test___.dart` | — |
| Swift | `_http_json_service_swift.swift` | `_http_json_call_swift.swift` | `_http_json_service_main_test___.swift` / `_http_json_call_main_test___.swift` | — |
| Ruby | `_http_json_service.rb` | `_http_json_call.rb` | `_http_json_service_main_test___.rb` / `_http_json_call_main_test___.rb` | — |
| Zig | `_http_json_service_zig.zig` | `_http_json_call_zig.zig` | `_http_json_service_main_test___.zig` / `_http_json_call_main_test___.zig` | `setup_zig_tests.ps1` |
| Erlang | `_http_json_service.erl` | `_http_json_call.erl` | `_http_json_service_main_test___.escript` / `_http_json_call_main_test___.escript` | `setup_erlang_tests.ps1` |
| Fortran | `_http_json_service_mod.f90` | `_http_json_call_mod.f90` | `_http_json_service_main_test___.f90` / `_http_json_call_main_test___.f90` | `setup_fortran_tests.ps1` |
| Julia | `_http_json_service.jl` | `_http_json_call.jl` | `_http_json_service_main_test___.jl` / `_http_json_call_main_test___.jl` | `setup_julia_tests.ps1` |
| R | `_http_json_service.R` + `_http_json_service_impl.R` | `_http_json_call.R` | `_http_json_service_main_test___.R` / `_http_json_call_main_test___.R` | `setup_r_tests.ps1` |
| Bridge | — | — | — | `launch_bridge.ps1` |

**通用后缀约定**：

- **没有 `_readme.md` 产物**（`.md` 生成功能已移除）。
- 每个 `FixedName = True` 的产物（`CMakeLists.txt` / `test_main___.cpp` / `launch_bridge.ps1` / `setup_*_tests.ps1`）都以精确名字写入，无 `<Unit>` 前缀。

---

## 附录 H — 术语表

| 术语 | 含义 |
|------|------|
| **LV0 JSON** | 解析器直接输出的中间表示。含源文本位置、原始类型拼写、修饰符。 |
| **LV1 Model** | 规范化后的中间模型。所有生成器的唯一输入。含 `UnitName`、`Functions`、`Params`、`Comments`。 |
| **ABI 家族** | 本工具链支持的三种类型集合：整数家族、浮点家族、字符串家族。 |
| **PascalType** | LV1 模型中的规范化类型字段。生成器依据此字段决定目标类型。 |
| **internal_call_<Api>** | 生成器中留给用户填实现体的桩函数。**不要重命名**；重新生成会丢失。 |
| **Bridge（桥接程序）** | `bridge.py` / `bridge.exe`。HTTP↔RPC 转发器。**必须始终运行**。 |
| **Beacon** | 注册智能体工具的 LingoFuse 服务（默认 `agent_main_app`）。 |
| **MCP** | Model Context Protocol。本工具通过它向智能体暴露 3 个工具。 |
| **TCompute.Sync** | 把嵌套过程调度到主线程并阻塞等待完成的同步原语。所有 UI 触碰都必须在它内部。 |
| **ApiName** | 规范化后的例程名。用于 URL 路径段、JSON 键、目标语言标识符。 |
| **MakeApiName** | 把任意字符串规范化为安全 ApiName 的函数。**所有生成器必须使用同一字符集替换规则**。 |
| **Target Language** | 生成产物的语言（Pascal / Python / C++ / C# / JavaScript / ...）。 |
| **Source Language** | 输入源文本的语言（仅 `pascal` / `c`）。 |
| **Wire Type** | JSON 线上类型。本工具链只用两种：`number` 与 `string`。 |
| **Fixed Name** | 不随 `<Unit>` 前缀变化的产物文件名（`CMakeLists.txt` / `test_main___.cpp` / `launch_bridge.ps1` / `setup_*_tests.ps1`）。 |
| **Readme（已移除）** | 曾经的 `*_readme.md` 产物。新版本不再生成。接口契约从代码本身读。 |
| **Service** | 服务侧。把函数注册为 LingoFuse Call API。 |
| **Call** | 调用侧。把本地函数调用转为 HTTP POST。 |
| **Test** | 测试程序。服务侧自测 + 调用侧端到端测试。 |
| **Bridge Setup** | 桥接程序启动脚本（`launch_bridge.ps1`）。 |
| **Setup Script** | 各语言的测试环境准备脚本（`setup_*_tests.ps1`）。 |
| **Stub Signature** | `internal_call_<Api>` 的签名。**接口契约的最终定义**。 |
| **CMake Target** | `CMakeLists.txt` 中 `add_executable` 的目标名。C++ 构建的唯一权威。 |
| **Test Driver** | `*_main_test___.*`。调用示例的最权威来源。 |

---

## 附录 I — 一句话总结各使用模式

- **GUI**：五个标签页，从左到右点击；出错就退回去修。**没有 `.md` 子标签**；接口契约从代码、CMake、测试驱动读。**CMake** 子标签持有两份 CMake 产物。
- **CLI**：`code_decl_to_json_abi [--call] [--lang <id>] input output`；扩展名决定语言，退出码决定成败。**没有 `<base>_readme.md`**；接口契约从代码读。C++ 目标还要看同目录的 `CMakeLists.txt` 与 `test_main___.cpp`。
- **智能体**：`Generate` → `ListFiles` → `GetFile`。三个工具，两步流程，一个会话。**没有 `.md` 可读**；从桩签名、测试驱动、CMake 脚本、`setup_*_tests.ps1` 读契约。
- **程序化**：直接调用 `Generate*Code` 函数；C++ 还要调 `GenerateCMakeScript` 与 `GenerateTestMainCpp`；C# 还要调 `GenerateHTTPServiceCsharpTestCode` 与 `GenerateHTTPCallCsharpTestCode`。**不再需要 `Generate*Readme`。**

**运行期必须永远记住的一条规则**：**桥接程序（`bridge.py` 或 `bridge.exe`）是转发器，必须始终运行。**

**生成后必须永远记住的一条规则**：**没有 `.md` 可读。从桩签名、测试驱动、CMake 脚本、`setup_*_tests.ps1`、生成代码顶部注释块读接口契约。** 见第 3 章与第 14 章。

---

*文档版本：v3 中文扩展版（无 Markdown 产物）*
*文档角色：code_decl_to_json_abi 的面向用户指南。更深入的架构参考见 code_decl_to_json_abi_knowledge_base.md。*