# LingoFuse-Tools

> **一份 Pascal 单元或一个 C 头文件，铺开整条跨语言接口线。**
>
> 代码、测试、构建脚本、知识库——从同一个模型长出来，不会漂移。

[LingoFuse](https://github.com/PassByYou888/LingoFuse) 是跨语言通讯地基。**LingoFuse-Tools** 是它的接口生成层：把你已经在写的 Pascal 函数或 C 函数，一次性变成任意目标语言可以**直接调用**的 service / call 代码——不需要写 IDL，不需要手写桩，不需要为每种语言重复维护一份“接口长什么样”。

---

## 这个仓库解决的真实问题：接口的维护熵增

跨语言接口最贵的不是“第一次写出来”，而是**改一次之后，所有语言、所有测试、所有构建脚本、所有文档能不能一起跟上**。

一个 `Add(a, b: Integer): Integer` 写出来，要在 Python 里写一遍调用、在 C++ 里写一遍 header/impl、在 C# 里写一遍 P/Invoke 封装、在测试里各写一遍断言、在 CMake 里加一个 target、在 README 里写一遍“这个 API 怎么用”。**每多一种语言，熵增翻一倍；每改一次签名，所有地方都可能留下一个不一致的字节。**

LingoFuse-Tools 做的事只有一件：**把“接口”从“维护物”变成“生成物”。**

你维护**一份声明**。生成器负责把这份声明投影到每一种目标语言、每一种协议、每一套测试和构建脚本上。改声明，重新生成，所有目标一起刷新。**不存在“C++ 改了但 Rust 忘了改”这种事，因为根本没有手写的“Rust 版本”需要去记。**

---

## 三条工具线：同一份声明，三种“到对面”的方式

仓库里不是“一个生成器”，而是**三条并行的投影线**。它们共享同一套解析器、同一套中间模型（LV1）、同一套类型白名单。区别只在**用什么协议把请求送到对面**，以及**产物集长什么样**。

| 工具 | 协议 | 一句话定位 |
|------|------|------------|
| **`code_decl_to_abi`** | LingoFuse 二进制 ABI | 两端都是 LingoFuse 原生时，走最短路径：定宽二进制、零 JSON 解析、零文本编码 |
| **`code_decl_to_json_abi`** | HTTP + JSON（经 `bridge.py`） | 一端是浏览器、外部 HTTP 客户端，或某种没有 LingoFuse 绑定的语言时，用 HTTP 把 LingoFuse 的 mesh 能力“借”出去 |
| **`code_decl_to_mcp`** | MCP（Model Context Protocol） | 把函数直接变成 AI Agent 可以发现的工具，不需要 Agent 懂 LingoFuse，只需要懂 MCP |

**选择规则可以压缩成一句话**：如果对面**能**加载 LingoFuse 运行时，优先用 ABI；如果对面**不能**，用 JSON ABI；如果对面是 **Agent**，用 MCP。

三者的产物集不同——ABI 出 service/call 源码和测试，JSON ABI 额外出 bridge 配置和 HTML 测试页，MCP 出 tool provider 和 tool schema——但**输入契约是同一份**。你在 `.pas` 或 `.h` 里写的东西，三条线都认。

---

## 应用规律：生成的边界由“类型白名单”划定，不由“语言”划定

LingoFuse-Tools 有一个不太像“代码生成器”的设计：**它不试图理解任意类型，只承认三个 ABI 家族——整数、浮点、字符串。**

这意味着：

- 一个函数**能不能被生成**，不取决于它是 Pascal 还是 C，不取决于目标语言是 Rust 还是 R，只取决于它的参数和返回值是否落在这三个家族里。
- `Boolean`、`Variant`、数组、记录、类、接口、枚举、指针、`TDateTime`——**整条声明被静默丢弃**，不是“部分生成”，不是“运行时再报错”。生成器在规范化阶段就把它们筛掉，日志里留一行原因。
- 复杂结构不能“透传”，但可以**降级**：把 JSON 塞进 `string`，对面自己反序列化。这是唯一被支持的“复杂类型逃生通道”。

这条规律决定了这个仓库的**适用形状**：它最适合**接口本身是数值/字符串密集**的系统——计算引擎、协议网关、数据管道、嵌入式控制面。如果接口天然是“传一个对象进来、改一个对象出去”，LingoFuse-Tools 会强迫你在声明层面做一次显式序列化决策，这是刻意的摩擦，不是缺陷。

---

## 工程定位：不是“又一个 gRPC 代码生成”，而是“跨语言接口的单一真相源”

gRPC 的 `.proto` 是**接口定义**，生成的是**桩**。LingoFuse-Tools 的 `.pas` / `.h` 是**实现本身**，生成的是**把实现暴露成远程可调用的那一层**。

这个差别带来三个工程后果：

**第一，它不要求你把接口从代码里“抽出来”。** 你的 Pascal 函数本来就在 `interface` 段里，C 函数本来就在头文件里。你不需要维护一份和实现分离的 IDL，也就不会出现“IDL 改了实现没改”或“实现改了 IDL 没改”的经典漂移。

**第二，它是“全产物”生成，不是“只生成客户端桩”。** 一次 `code_decl_to_abi` 会同时产出 service 侧（把函数注册进 mesh）、call 侧（让别的语言能调它）、测试程序（端到端跑通）、构建脚本（CMake / Cargo / Maven / …）和知识库（这个产物怎么构建、怎么部署、怎么排错）。**调用方拿到的不只是一份“可以调用的 API”，而是一整条从编译到运行的路径。**

**第三，它是“Agent 原生”的，不是“Agent 兼容”的。** 每个工具本身就是 MCP tool provider，每个工具都自带一份给 AI 读的知识库（输入契约、线格式、踩坑记录、调试树）。**Agent 不需要读生成器源码就能驱动整个工具链**——它通过 MCP 调 `Generate`，然后读知识库来理解生成出来的东西。这是这个仓库和大多数“AI-friendly”工具最本质的区别：**AI 是主用户，不是附加功能。**

---

## 统一能力：四个前端入口，一个后端

三个工具**全部**共享同一套前端形态。没有“这个工具有 GUI 但那个只有 CLI”的分裂。

| 能力 | 具体形态 |
|------|----------|
| **GUI** | 五标签页向导：Welcome → Source Code → Source ↔ JSON → JSON ↔ Model → Final Source。每一步可以手工检查/修正中间 JSON，不是黑盒 |
| **CLI** | 文件到文件，无 UI，退出码语义明确（0 成功 / 1 参数错 / 2 解析失败 / 3 生成失败 / 4 I/O 错） |
| **MCP** | GUI 启动后自动注册为 MCP tool provider。`code_decl_to_abi` 暴露 31 个工具，`code_decl_to_json_abi` 3 个，`code_decl_to_mcp` 11 个——数量不同是因为工作流粒度不同，不是能力差异 |
| **程序化接口** | 每个生成器都是独立的 Pascal 单元，导出 `GenerateXxxCode(Model)` 函数。你可以绕过所有前端，直接在自己的 Pascal 程序里调用 |

**GUI / CLI / MCP 三者的输出是字节一致的。** MCP 层的 `internal_call_*` 内部就是调用 GUI 的按钮处理器，不存在“MCP 路径悄悄做了不一样的事”。

---

## 目标语言：当前交付集是“五语言口径”，但架构没有天花板

仓库当前的**已交付、可工作**的目标语言集是：

| 语言 | ABI | HTTP/JSON | MCP |
|------|:---:|:---------:|:---:|
| Pascal | ✅ | ✅ | ✅ |
| Python | ✅ | ✅ | ✅ |
| C++ | ✅ | ✅ | ✅ |
| C# | ✅ | ✅ | ✅ |
| JavaScript（浏览器 / Node） | —（仅 call） | ✅ | — |

**这不是“最终支持列表”**，而是“今天能直接跑的列表”。仓库的架构把加一种新目标语言定义为**机械操作**：两个生成器单元、一张类型映射表、在四个地方注册（主程序 / CLI / GUI / MCP 工具提供者）、一条 CLI 扩展名识别、一个 MCP 工具计数常量。**没有架构变更，没有“核心需要重构”。**

路线图上的 30 种语言覆盖系统语言（Rust / Go / Zig / Nim / D / Swift / Kotlin Native）、JVM 系（Java / Kotlin / Scala）、.NET 系（F# / VB.NET）、函数式（OCaml / Haskell / Elixir / Erlang）、脚本（Ruby / PHP / Perl / Lua / Julia / TypeScript）、领域专用（R / MATLAB / Wolfram）和嵌入式（MicroPython / embedded C / Ada / SPARK）。**加语言时用户契约不变**：同样的 CLI 标志、同样的 GUI 标签页、同样的 MCP 工具名。

---

## 快速开始

**前置条件**：Free Pascal 3.2+ 或 Delphi 10.4+；Lazarus（GUI 构建）或 `fpc` 命令行；zCore 子模块已初始化；LingoFuse 运行时（`LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` + `z_ipc_*`）在 `PATH` 或工具可执行文件同目录。

```bash
git submodule update --init --recursive
lazbuild -B src/pascal_c_to_abi/code_decl_to_abi.lpi
lazbuild -B src/pascal_c_to_json_abi/code_decl_to_json_abi.lpi
lazbuild -B src/pascal_c_to_mcp/code_decl_to_mcp.lpi
# 或 Windows 下直接 src/build.bat
```

**GUI**：不带参数运行任意工具。

**CLI 最小示例**：

```bash
# Pascal → Pascal service
code_decl_to_abi calculator.pas calculator_service.pas

# C header → C# service（完整产物集：service + call + 两个测试 + 测试 README）
code_decl_to_abi --call math.h math_service.cs

# C header → C++ service（自动配对 .hpp + .cpp + CMakeLists + 测试驱动）
code_decl_to_json_abi ComplexTestUnit.h calculator_service.hpp

# Pascal → MCP tool provider
code_decl_to_mcp calculator.pas calculator_provider.pas
```

**MCP**：GUI 启动后，工具自动向 `agent_main_app` beacon 注册。以 `code_decl_to_mcp` 为例，Agent 只需要三步：`SetSourceCode` → `ConvertToXxxMCP` → `GetLastXxxCode/Readme`。没有 GUI 交互，没有 CLI 调用，和调用任何其他 MCP tool 没有区别。

---

## 知识库：给 AI 读的“接口手册”，和代码同源

每个工具都自带一份知识库，内容不是“人类写的教程”，而是**AI 可以直接消费的契约**：

- **输入契约**（`pascal_code_abi_rule.md` / `C_code_abi_rule.md`）：哪些声明会被提取、哪些会被静默丢弃、参数名必须出现在行首、`{ }` 注释里不能有 `}`、C 的 `void *` 为什么会在 Pascal 侧被拒绝——**每一条规则都有 ✅/❌ 代码示例**。
- **线协议**（`MCP_API_Contract.md`）：UTF-8 + NUL 帧、状态字节语义、`required` 数组包含所有参数、`ensure_ascii=False` 的强制要求——**字节级，不是伪代码级**。
- **踩坑记录**（`R_ABI_Generator_Knowledge_Base.md` / `Dart_ABI_Generators_Fix_Report.md` / `Fortran_ABI_Generator_Work_Report.md` / `swift_abi_generator_development_log.md` / `TypeScript_ABI_Generator_Development_Report.md` / `LingoFuse_JS_Async_Generator_Fix_Knowledge_Base.md`）：记录了“我以为”被实测推翻的地方——`int64` 在 JS 丢精度、`_timer.unref()` 让 async 永远卡死、Ruby 的 dispatcher 线程在 DLL 卸载后访问野指针、Swift 的 `LF_LoadLibrary` 漏调用导致所有 `LF_*` 静默失败。

**喂给 Agent，Agent 就能接管这个工具。** 这是仓库的设计承诺：知识库不是“文档”，是**可执行的接口规格**。

---

## 仓库结构（速览）

```
src/
├── pascal_c_to_abi/          ← code_decl_to_abi（二进制 ABI）
│   ├── code_decl_to_abi.lpr  ← 主程序（CLI/GUI 分发）
│   ├── code_decl_to_abi_frm.pas
│   ├── code_decl_to_abi_cmdline.pas
│   ├── *_abi_*_generator_tool.pas  ← 各语言生成器
│   └── *_rule.md / *Knowledge*.md  ← 输入契约 + 踩坑库
├── pascal_c_to_json_abi/     ← code_decl_to_json_abi（HTTP/JSON）
│   ├── http_bridge_setup_generator_tool.pas  ← bridge 启动脚本
│   └── http_*_abi_*_generator_tool.pas
├── pascal_c_to_mcp/          ← code_decl_to_mcp（MCP）
│   ├── *_mcp_generator_tool.pas
│   └── MCP_API_Contract.md
├── common/                   ← 共享底层（lingofuse_import / helper）
└── zCore/                    ← Z 框架子模块
```

每个工具目录下**生成器单元和知识库并排**——这是刻意的：读生成器行为和读契约文档在同一个视野里，不会出现“代码在这里、文档在另一个仓库”的断裂。

---

## 这个仓库不适合谁

- **想要“装好就能跑、一条命令出全部语言”的人**：生成器本身需要 FPC/Lazarus 构建，目标语言的构建脚本需要你该语言的工具链。生成器只保证“生成出来的代码是完整的”，不保证“你的机器上什么编译器都装好了”。
- **接口天然是“对象进、对象出”的人**：三个 ABI 家族之外的类型会被丢弃。你需要先在声明层面做序列化决策，这不是生成器替你做的事。
- **需要成熟社区、Stack Overflow 问答、第三方教程的人**：单人维护，Issue 会回，但没有 SLA。

**反过来**：如果你需要**把一组已经在用的 Pascal / C 函数，以最小的手工维护成本暴露给多种语言**，并且你接受“只支持整数 / 浮点 / 字符串、复杂结构自己序列化成字符串”这个边界，那这个仓库是目前能找到的最接近“单一真相源”的实现。

---

**相关**：[LingoFuse](https://github.com/PassByYou888/LingoFuse)（通讯地基） · [LingoFuse-pasAgent-v3](https://github.com/PassByYou888/LingoFuse-pasAgent-v3)（Agent 与 MCP 运行时） · [zIPC](https://github.com/PassByYou888/zIPC)（底层同机 IPC）

**许可证**：MIT