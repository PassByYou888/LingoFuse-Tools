# code_decl_to_json_abi 使用说明

> 本文档描述 **如何使用** `code_decl_to_json_abi` 工具，包括：
> 图形界面（GUI）操作、命令行（CLI）操作、以及在智能体（MCP / LingoFuse）中远程调用。
>
> 不涉及源码结构，不涉及编译细节。只讲怎么用。

---

## 目录

1. [项目概览](#1-项目概览)
2. [⚠️ 全局前置：bridge 必须常开](#2-️-全局前置bridge-必须常开)
3. [环境准备](#3-环境准备)
4. [GUI 操作](#4-gui-操作)
5. [命令行操作](#5-命令行操作)
6. [智能体（MCP）操作](#6-智能体mcp操作)
7. [产物清单](#7-产物清单)
8. [常见问题](#8-常见问题)

---

## 1. 项目概览

`code_decl_to_json_abi` 是一个**原型声明 → HTTP/JSON 接口代码生成器**。

给它一份 Pascal 单元或 C 头文件，它会：

1. 解析出所有顶层函数/过程声明；
2. 归一化为中间模型（Model）；
3. 生成一整套 **HTTP POST + JSON** 接口代码，覆盖 5 个语言方向、共 17 个文件。

支持的**源语言**只有两种：

- Pascal（`.pas` / `.pp` / `.p`）
- C（`.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx`）

支持的**目标语言**共 5 种，服务端与调用端分别生成：

| 目标 | 服务端（暴露接口） | 调用端（发起调用） |
|------|---------------------|---------------------|
| Pascal | ✅ `<unit>_http_json_service_unit.pas` | ✅ `<unit>_http_json_call_unit.pas` |
| Python | ✅ `<unit>_http_json_service.py` | ✅ `<unit>_http_json_call.py` |
| C++ | ✅ `.hpp` + `.cpp` 双文件 | ✅ `.hpp` + `.cpp` 双文件 |
| JavaScript | ❌（不支持服务端） | ✅ `.js` + 自带测试页 `.html` |
| 每个目标配套 | ✅ Markdown README | ✅ Markdown README |

**一句话理解**：你写一份 Pascal/C 的“声明”，工具帮你把跨语言、跨进程的 RPC 接口全部铺好。

---

## 2. ⚠️ 全局前置：bridge 必须常开

> **这是使用本工具生成的所有接口代码的最重要前提，务必先读这一节。**

### 2.1 bridge 是什么

**`bridge.py`（或编译好的 `bridge.exe`）是 LingoFuse 提供的 HTTP↔RPC 转发工具。**

它的职责只有一个：**把 HTTP 请求翻译成 LingoFuse 内部调用，再把返回值翻译回 HTTP 响应。**

```
HTTP 客户端  ──HTTP POST──▶  bridge.py / bridge.exe  ──LF_Call──▶  服务端
HTTP 客户端  ◀─HTTP 响应──   bridge.py / bridge.exe  ◀─LF 返回──  服务端
```

### 2.2 为什么必须常开

本工具生成的**所有调用端代码**（Pascal / Python / C++ / JavaScript）以及**自带的 HTML 测试页**，都**不直接**和服务端通信，而是统一走 bridge：

- **Pascal 调用端**：内部 `LFHttpPost` 通过 LingoFuse 把请求打到 bridge。
- **Python 调用端**：用 `requests.post(...)` 打到 bridge 的 HTTP 端点。
- **C++ 调用端**：通过 LingoFuse C ABI 打到 bridge。
- **JavaScript 调用端**：用 `fetch(...)` 直接 POST 到 bridge 的 HTTP 端点。
- **HTML 测试页**：同上。

**只要 bridge 不在线，以上所有调用端和测试页都会立即失败**，典型表现是：

- `EHTTPCallError: ... Network error`（Pascal / C++）；
- `HTTPCallError: Network error`（Python）；
- `Failed to fetch` / CORS 错误（JS / 浏览器）；
- `Connection refused`（curl 手测）。

### 2.3 bridge 的生命周期规则

| 规则 | 说明 |
|------|------|
| **必须单独启动** | bridge 是一个独立的进程，与你的调用端、服务端**分别运行**。 |
| **必须常驻** | 只要你还打算调用接口或运行测试页，bridge **就必须一直开着**。 |
| **不能共用终端** | 建议在**独立终端**里启动 bridge，不要和调用端 / 服务端挤在一个终端。 |
| **必须先于调用端就绪** | 建议启动顺序：**服务端 → bridge → 调用端**。 |
| **重新启动即重新拉起** | bridge 崩溃或被杀之后，重新运行 bridge 即可恢复服务；调用端不需要重启。 |

### 2.4 三个进程的推荐布局

```
终端 1（服务端）：          启动生成的服务端（Pascal / Python / C++）
终端 2（bridge）：          python3 bridge.py --endpoint <与服务端一致的 endpoint> --port 8081 --no-precheck
终端 3（调用端 / 测试页）：启动生成的调用端，或双击 HTML 测试页
```

**bridge 在终端 2 必须保持前台运行**。看到它打出 HTTP 监听日志后，才能开始调用。

### 2.5 常见误解

- ❌ “生成了代码就能直接调用。” → 必须 bridge 在跑。
- ❌ “我只在 GUI 里生成代码，不需要 bridge。” → **GUI 生成阶段确实不需要 bridge**，但**运行生成出来的代码/测试页时必须开 bridge**。
- ❌ “bridge 和 服务端 二选一就行。” → **两者必须同时在跑**，bridge 是转发工具，服务端才是真正的业务逻辑。
- ❌ “bridge 只需要跑一次，以后可以关。” → 关闭 bridge = 关闭整条 HTTP↔RPC 通路。

> **记住一句话：bridge（`bridge.py` / `bridge.exe`）是转发工具，必须保持开启。**
> 生成的所有调用端、测试页都依赖它。

---

## 3. 环境准备

### 3.1 直接运行

从可执行文件所在的目录运行 `code_decl_to_json_abi` 即可。程序会自动在自身目录下查找：

- `pascal_code_abi_rule.md`（Pascal 原型规则）
- `C_code_abi_rule.md`（C 原型规则）

不找到不影响使用，只是 GUI 里的“规则文档”按钮点不开。

### 3.2 生成阶段的依赖

- **生成阶段（GUI / CLI）无额外依赖**。工具本身不联网，也不使用 bridge。
- **运行生成出来的代码 / 测试页**时，才需要 bridge 与服务端。

### 3.3 运行阶段的依赖

| 组件 | 用途 | 是否必须 |
|------|------|----------|
| **服务端**（生成的 `*_service_*` 代码编译/运行后得到的进程） | 提供业务逻辑 | ✅ 必须 |
| **bridge**（`bridge.py` 或 `bridge.exe`） | HTTP ↔ RPC 转发 | ✅ **必须常开** |
| **调用端**（生成的 `*_call_*` 代码编译/运行后得到的进程，或 HTML 测试页） | 发起调用 | 按需 |

### 3.4 智能体模式

智能体模式需要 LingoFuse 运行时：

- `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`
- `z_ipc_*.dll` / `libz_ipc_*.so`
- Beacon 服务（`agent_main_app`）必须在线

如果只做本地 GUI / CLI，不需要任何运行时依赖。

---

## 4. GUI 操作

### 4.1 启动 GUI

**不带任何命令行参数**双击运行，直接进入 GUI。

GUI 顶部有 5 个工作页（Tab），从左到右依次推进：

```
[1. Welcome] → [2. Source Code] → [3. Source <-> JSON] → [4. JSON <-> Model] → [5. Final Source]
```

每个 Tab 页顶部都有一排按钮，指引“上一步 / 下一步”。

### 4.2 第 1 页：Welcome

- 显示工具的整体说明、架构图、工作流。
- 右侧按钮：
  - **Pascal rule doc**：打开 `pascal_code_abi_rule.md`。
  - **C rule doc**：打开 `C_code_abi_rule.md`。
- **Next: Enter source code**：跳到第 2 页。

### 4.3 第 2 页：Source Code

这一页是**输入代码**的地方。

顶部工具栏：

| 控件 | 作用 |
|------|------|
| **Select Language 提示标签** | 点击后自动检测语言。 |
| **Language Selector 下拉框** | `Auto-detect` / `Pascal` / `C` 手动选择。 |
| **Format** | 只保留顶层函数，重建最小声明。 |
| **Empty unit** | 插入最小骨架（Pascal 或 C）。 |
| **Test unit** | 插入覆盖各种语法形态的复杂示例（推荐首次体验时用）。 |
| **Next: Pascal/C -> JSON** | 解析当前源码，生成 LV0 JSON，跳到第 3 页。 |

操作步骤：

1. 粘贴你的 Pascal 单元或 C 头文件到编辑区。
2. 若不确定语言，点击“Select Language”标签让工具自动检测。
3. 若发现语法高亮不对，手动从下拉框选择语言。
4. 点击 **Next: Pascal/C -> JSON**。

### 4.4 第 3 页：Source <-> JSON

这一页展示的是**解析器输出的原始 JSON（LV0）**。

顶部按钮：

| 按钮 | 作用 |
|------|------|
| **Back: rebuild code from JSON** | 把当前 JSON 反向重建为源码，写回第 2 页。 |
| **Next: JSON <-> Model** | 把 LV0 归一化为 LV1 模型，跳到第 4 页。 |

你可以在这里**手动修正 JSON**——例如解析器对某个类型判断不准，可以直接改 JSON 里的字符串，再点“Next”继续。反向重建按钮用于验证你的修改是否仍然合法。

### 4.5 第 4 页：JSON <-> Model

这一页展示的是**归一化后的模型 JSON（LV1）**。

顶部按钮：

| 按钮 | 作用 |
|------|------|
| **Back: JSON <-> Model** | 反向把 LV1 还原为 LV0，写回第 3 页。 |
| **Next: generate source** | 生成全部 17 个文件，跳到第 5 页。 |

**提示**：模型 JSON 会自动剔除不支持的类型（`Boolean`、`Variant`、数组、记录、类、接口、枚举、集合、指针、`Currency`、`TDateTime` 等）。如果某个函数没有出现在最终产物里，多半是它的参数或返回值里有不支持的 ABI 类型。

### 4.6 第 5 页：Final Source

这一页有 8 个子 Tab：

| 子 Tab | 内容 |
|--------|------|
| Pascal Service | Pascal 服务端代码 + README |
| Pascal Call | Pascal 调用端代码 + README |
| JavaScript Call | JS 客户端代码 + README |
| JavaScript Test HTML | 自包含的 HTML 测试页 |
| Python Service | Python 服务端代码 + README |
| Python Call | Python 调用端代码 + README |
| C++ Service | C++ 服务端 .hpp + .cpp + README |
| C++ Call | C++ 调用端 .hpp + .cpp + README |

**文件已经落盘**：生成时所有文件自动写到**可执行文件所在目录**下的 `<UnitName>/` 子目录里，文件名格式为 `<UnitName>_http_json_*.xxx`。

顶部按钮：

- **Back: Model JSON**：返回第 4 页继续调整模型。

---

## 5. 命令行操作

### 5.1 触发条件

命令行模式**只在至少传入一个参数时**触发。无参数 = GUI。

程序以 console 子系统构建，因此：

- 双击运行 = 启动 GUI（系统会额外弹出一个空控制台窗口，关闭主窗口即结束）。
- 命令行运行 = 所有 `DoStatus` 消息直接打到 stdout，正常工作后按退出码返回。

### 5.2 语法

```
code_decl_to_json_abi --help
code_decl_to_json_abi <input_file> <output_file>
code_decl_to_json_abi --call <input_file> <output_file>
```

| 参数 | 说明 |
|------|------|
| `--help` / `-h` / `-?` / `/?` | 打印帮助后退出。**只识别为第 1 个参数。** |
| `--call` / `-c` | 生成调用端。**只识别为第 1 个参数**，缺省为服务端。 |
| `<input_file>` | 输入源文件。语言由**扩展名**判断。 |
| `<output_file>` | 输出文件。目标语言由**扩展名**判断。 |

### 5.3 输入扩展名 → 源语言

| 扩展名 | 源语言 |
|--------|--------|
| `.pas` / `.pp` / `.p` | Pascal |
| `.h` / `.hpp` / `.hh` / `.c` / `.cpp` / `.cc` / `.cxx` | C |

### 5.4 输出扩展名 → 目标语言

| 扩展名 | 目标语言 | 支持的方向 |
|--------|----------|------------|
| `.pas` / `.pp` / `.p` | Pascal | 服务端 + 调用端 |
| `.py` | Python | 服务端 + 调用端 |
| `.hpp` / `.hh` / `.h` / `.cpp` / `.cc` / `.cxx` / `.c` | C++（.hpp + .cpp 双文件） | 服务端 + 调用端 |
| `.js` | JavaScript | **仅调用端** |

**JavaScript 是调用端专用**：指定 `.js` 输出但没有传 `--call`，工具会直接以参数错误退出。

### 5.5 每次运行会产出什么

以 `<output>` 的基名为准（去掉扩展名），自动写入**同目录**下的产物：

- **代码文件**：`<base>.xxx`（Pascal / Python / JS 单文件；C++ 会产出 `<base>.hpp` + `<base>.cpp` 双文件）。
- **配套 README**：`<base>_readme.md`。
- **JS 特有**：额外产出 `<base>_test.html`（自包含测试页）。

### 5.6 示例

**服务端：Pascal → Pascal**

```
code_decl_to_json_abi calculator.pas calculator_service.pas
```

产物：

```
calculator_service.pas
calculator_service_readme.md
```

**调用端：Pascal → Pascal**

```
code_decl_to_json_abi --call calculator.pas calculator_call.pas
```

**服务端：C → Python**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_service.py
```

**调用端：C → Python**

```
code_decl_to_json_abi --call ComplexTestUnit.h calculator_call.py
```

**服务端：C → C++（.hpp + .cpp 双文件）**

```
code_decl_to_json_abi ComplexTestUnit.h calculator_service.hpp
```

产物：

```
calculator_service.hpp
calculator_service.cpp
calculator_service_readme.md
```

**调用端：C → JavaScript（.js + .html 双文件）**

```
code_decl_to_json_abi --call ComplexTestUnit.h calculator_call.js
```

产物：

```
calculator_call.js
calculator_call_readme.md
calculator_call_test.html
```

### 5.7 退出码

| 退出码 | 含义 |
|--------|------|
| `0` | 转换成功。 |
| `1` | 参数缺失或非法。 |
| `2` | 源码解析失败（`ParseSuccess=False`，或找不到任何可用声明）。 |
| `3` | 代码生成失败（生成器返回 nil）。 |
| `4` | 文件 I/O 错误（读入或写出失败）。 |

### 5.8 输出消息

命令行模式下，所有中间消息都走 stdout，例如：

```
Reading: ComplexTestUnit.h (1234 chars)
Output : calculator_service.py
Mode   : service
Unit   : ComplexTestUnit
Funcs  : 28
Saved  : calculator_service.py
Saved  : calculator_service_readme.md
Done.
```

出现错误时会打印 `Failed.` 并以非零退出码返回。

### 5.9 ⚠️ 命令行不启动 bridge

**CLI 只负责生成代码，不启动 bridge，也不启动服务端。**

生成完成后，要真正跑通一次端到端调用，必须手动：

1. 编译 / 运行生成的服务端；
2. **单独启动 `bridge.py`（或 `bridge.exe`）并保持常开**；
3. 再运行调用端或打开 HTML 测试页。

---

## 6. 智能体（MCP）操作

### 6.1 触发条件

**GUI 启动后**，工具会在后台线程自动启动 MCP 服务：

1. 创建 LingoFuse App（默认名 `code_decl_to_json_abi_mcp_api`）。
2. 连接 LingoFuse endpoint（默认 `ipc:agent`）。
3. 通过 Beacon（默认 App `agent_main_app`，API `register_agent`）注册全部 **22 个工具**。

所以智能体要调用本工具，必须：

- 本工具的 GUI **正在运行**；
- Beacon（例如 `pascal_agent_service`）**正在运行**；
- 二者 LingoFuse endpoint 一致（默认 `ipc:agent`）。

> **注意**：智能体模式下的 MCP 服务与 bridge **是两回事**。
> - MCP 服务：让智能体调用本工具的 22 个 API（生成代码）。
> - bridge：让运行阶段的所有调用端能访问服务端。
>
> **两者互不替代。** 智能体生成代码时不需要 bridge；但生成的代码要跑起来，仍然**必须开 bridge**。

### 6.2 工具清单（22 个）

按功能分 4 组。

#### 6.2.1 写入 / 检查（Step 1 与 Step 3 的“只读”查询）

| 工具名 | 作用 |
|--------|------|
| `CodeDeclToJsonAbi_SetSourceCode` | **Step 1**：把源码字符串（Pascal 或 C）塞进“源代码编辑器”，并选择源语言。参数：`Source`、`Language`（`"pascal"` 或 `"c"`）。 |
| `CodeDeclToJsonAbi_SetModelJson` | **Step 1 的替代**：直接塞入一个 LV1 模型 JSON。参数：`ModelJson`。 |
| `CodeDeclToJsonAbi_GetSourceJson` | **只读**：取回当前 LV0 源码 JSON。 |
| `CodeDeclToJsonAbi_GetModelJson` | **只读**：取回当前 LV1 模型 JSON。 |

> `SetSourceCode` 和 `SetModelJson` 是**互斥的两条入口**。用哪个都可以，但一旦用了 `SetModelJson` 就直接跳过解析器与归一化器。

#### 6.2.2 生成（Step 2）

| 工具名 | 作用 |
|--------|------|
| `CodeDeclToJsonAbi_GenerateAll` | **Step 2**：跑完 17 个生成器，并把结果缓存到 17 个编辑器里。返回 JSON，含 `unit_name` 和 `files` 清单。 |

`GenerateAll` 可以重复调用，每次都针对当前模型 JSON 重跑全部生成器。

#### 6.2.3 读取产物（Step 3，共 17 个只读工具）

按目标语言与方向分组：

**Pascal**

| 工具名 | 产物 |
|--------|------|
| `CodeDeclToJsonAbi_GetLastPascalServiceCode` | Pascal 服务端代码 |
| `CodeDeclToJsonAbi_GetLastPascalServiceReadme` | Pascal 服务端 README |
| `CodeDeclToJsonAbi_GetLastPascalCallCode` | Pascal 调用端代码 |
| `CodeDeclToJsonAbi_GetLastPascalCallReadme` | Pascal 调用端 README |

**JavaScript**

| 工具名 | 产物 |
|--------|------|
| `CodeDeclToJsonAbi_GetLastJsCallCode` | JS 客户端 |
| `CodeDeclToJsonAbi_GetLastJsCallReadme` | JS README |
| `CodeDeclToJsonAbi_GetLastJsTestHtml` | HTML 测试页 |

**Python**

| 工具名 | 产物 |
|--------|------|
| `CodeDeclToJsonAbi_GetLastPythonServiceCode` | Python 服务端 |
| `CodeDeclToJsonAbi_GetLastPythonServiceReadme` | Python 服务端 README |
| `CodeDeclToJsonAbi_GetLastPythonCallCode` | Python 调用端 |
| `CodeDeclToJsonAbi_GetLastPythonCallReadme` | Python 调用端 README |

**C++**

| 工具名 | 产物 |
|--------|------|
| `CodeDeclToJsonAbi_GetLastCppServiceHeader` | C++ 服务端 `.hpp` |
| `CodeDeclToJsonAbi_GetLastCppServiceImpl` | C++ 服务端 `.cpp` |
| `CodeDeclToJsonAbi_GetLastCppServiceReadme` | C++ 服务端 README |
| `CodeDeclToJsonAbi_GetLastCppCallHeader` | C++ 调用端 `.hpp` |
| `CodeDeclToJsonAbi_GetLastCppCallImpl` | C++ 调用端 `.cpp` |
| `CodeDeclToJsonAbi_GetLastCppCallReadme` | C++ 调用端 README |

所有 17 个读取器都是**纯读**，不会触发新的解析或生成。

### 6.3 推荐调用序列

**最小流程（只需要一份产物）**：

```
1. CodeDeclToJsonAbi_SetSourceCode(Source="...", Language="pascal")
2. CodeDeclToJsonAbi_GenerateAll()
3. CodeDeclToJsonAbi_GetLastPythonServiceCode()      ← 按需取你想要的
```

**只读取解析/模型的检查流程**：

```
1. CodeDeclToJsonAbi_SetSourceCode(Source="...", Language="c")
2. CodeDeclToJsonAbi_GetSourceJson()                 ← 看 LV0
3. CodeDeclToJsonAbi_GetModelJson()                  ← 看 LV1（自动归一化后的结果）
```

**直接注入已有模型的流程**：

```
1. CodeDeclToJsonAbi_SetModelJson(ModelJson="...")
2. CodeDeclToJsonAbi_GenerateAll()
3. 按需调用 17 个读取器
```

### 6.4 工具返回值

所有工具的返回值都是 **JSON 字符串**。

`SetSourceCode` / `SetModelJson` 成功：

```json
{"status":"ok","unit_name":"Calculator"}
```

`GenerateAll` 成功：

```json
{
  "status":"ok",
  "unit_name":"Calculator",
  "files":{
    "pascal_service_code":   "Calculator_http_json_service_unit.pas",
    "pascal_service_readme": "Calculator_http_json_service_pascal.md",
    "pascal_call_code":      "Calculator_http_json_call_unit.pas",
    "pascal_call_readme":    "Calculator_http_json_call_pascal.md",
    "js_call_code":          "Calculator_http_json_call.js",
    "js_call_readme":        "Calculator_http_json_call_js.md",
    "js_test_html":          "Calculator_http_json_call_test.html",
    "python_service_code":   "Calculator_http_json_service.py",
    "python_service_readme": "Calculator_http_json_service_python.md",
    "python_call_code":      "Calculator_http_json_call.py",
    "python_call_readme":    "Calculator_http_json_call_python.md",
    "cpp_service_header":    "Calculator_http_json_service.hpp",
    "cpp_service_impl":      "Calculator_http_json_service.cpp",
    "cpp_service_readme":    "Calculator_http_json_service_cpp.md",
    "cpp_call_header":       "Calculator_http_json_call.hpp",
    "cpp_call_impl":         "Calculator_http_json_call.cpp",
    "cpp_call_readme":       "Calculator_http_json_call_cpp.md"
  }
}
```

失败：

```json
{"error":"<message>"}
```

**17 个读取器** 成功时直接返回**产物全文**（纯文本，不是 JSON）；失败时返回空字符串。

### 6.5 智能体操作注意事项

1. **源语言只接受 `"pascal"` 或 `"c"`**，其他值会被拒绝。
2. **不要在一次会话中交替使用 `SetSourceCode` 和 `SetModelJson`**——后一次调用会完全覆盖前一次的状态，`GetSourceJson` 只对 `SetSourceCode` 有效。
3. **`GenerateAll` 是幂等的**：重复调用不会累积垃圾，只会重写 17 个缓存。
4. **先 `SetSourceCode`/`SetModelJson`，再 `GenerateAll`，最后读取**——顺序反过来会失败。
5. **17 个读取器只对“最近一次成功的 `GenerateAll`”有效**：在调用 `GenerateAll` 之前调用它们，只会得到空字符串。
6. **GUI 必须活着**：MCP 服务是 GUI 启动时挂上的，GUI 关闭后工具全部下线。
7. **智能体生成代码 ≠ 运行代码**：生成出来的代码要跑起来，**仍然必须手动启动 bridge 并保持常开**。

---

## 7. 产物清单

### 7.1 每种产物的用途

| 文件后缀 / 名称 | 用途 | 运行阶段是否需要 bridge |
|-----------------|------|--------------------------|
| `*_http_json_service_unit.pas` | Pascal 服务端：注册 API、监听 RPC、把 LingoFuse 调用转成 JSON。 | ❌（服务端不经过 bridge） |
| `*_http_json_call_unit.pas` | Pascal 调用端：把本地函数调用转成对 bridge.py 的 HTTP POST。 | ✅ **必须** |
| `*_http_json_service.py` | Python 服务端。 | ❌ |
| `*_http_json_call.py` | Python 调用端。 | ✅ **必须** |
| `*_http_json_service.hpp` / `.cpp` | C++ 服务端（.hpp 声明 + .cpp 实现）。 | ❌ |
| `*_http_json_call.hpp` / `.cpp` | C++ 调用端。 | ✅ **必须** |
| `*_http_json_call.js` | 浏览器 JS 客户端（IIFE 形式，挂到 `window.<UnitName>Api`）。 | ✅ **必须** |
| `*_http_json_call_test.html` | 自包含的 HTML 测试页，双击即可测试。 | ✅ **必须** |
| `*_readme.md` | 每种产物的配套说明（含 wire protocol、类型映射、示例）。 | — |

> **注意**：**服务端本身不经过 bridge**。bridge 只服务于“调用端 → 服务端”的方向。
> 也就是说，bridge 要转发的是**调用端的请求**，它把调用端的 HTTP 翻译成 LingoFuse 调用发往服务端。

### 7.2 文件位置

- **GUI / 命令行**：产物写在**可执行文件所在目录**下的 `<UnitName>/` 子目录里。
- **智能体（MCP）**：产物与 GUI 版一致，同样写在可执行文件目录下的 `<UnitName>/`；同时 17 个编辑器的内容会通过读取器原样返回给智能体。

### 7.3 配套 bridge：转发工具，必须常开

**生成的调用端（Pascal / Python / C++ / JavaScript）都通过 bridge 与后端通信：**

```
调用端 ──HTTP POST──▶ bridge.py / bridge.exe ──LF_Call──▶ 服务端
调用端 ◀─HTTP 响应── bridge.py / bridge.exe ◀─LF 返回── 服务端
```

**启动 bridge 时需要指定与服务端一致的 endpoint，例如：**

```
python3 bridge.py --endpoint ipc:calc_http_json --port 8081 --no-precheck
```

或（编译好的可执行版本）：

```
bridge.exe --endpoint ipc:calc_http_json --port 8081 --no-precheck
```

`--no-precheck` 会跳过 bridge 的 API 预检查（约 3 秒延迟），首次启动更稳。

**重要规则再强调一次**：

- **bridge 是转发工具，必须保持开启**。关闭 bridge = 关闭整条通路。
- bridge 可以 `bridge.py` 运行，也可以编译成 `bridge.exe` 运行，两者行为一致。
- bridge 应放在**独立终端**里前台运行，看到 HTTP 监听日志后，再去运行调用端。
- 崩溃/被杀后，重启 bridge 即可恢复；调用端无需重启。

---

## 8. 常见问题

### Q1：为什么我传进去的函数没有出现在生成结果里？

检查三点：

1. **函数是否在顶层**（`interface` 段，非嵌套在 `class` / `record` 里）。嵌套声明会被跳过。
2. **参数与返回类型是否在支持列表中**：只接受整数族、浮点族、字符串族。`Boolean`、`Variant`、数组、记录、类、接口、枚举、集合、指针、`Currency`、`TDateTime` 都不支持。
3. **函数名是否非空**（`Name.Len > 0`）。

### Q2：为什么模型 JSON 里函数比源文件少？

同上。归一化时会把不支持类型的函数整体剔除。

### Q3：CLI 输出 `.js` 但没传 `--call` 会怎样？

直接以参数错误退出，退出码 `1`。JavaScript 是调用端专用目标。

### Q4：CLI 运行后没看到任何输出？

本工具在 CLI 模式下把所有 `DoStatus` 消息写到 stdout。如果你在 IDE 里运行或重定向了 stdout，就可能看不到。直接在终端里跑即可。

### Q5：GUI 里“规则文档”按钮点了没反应？

可执行文件目录下缺少 `pascal_code_abi_rule.md` 或 `C_code_abi_rule.md`。把这两个文件放到可执行文件旁边即可。

### Q6：智能体调用工具返回 `{"error":"Form not available"}`？

GUI 没有运行。MCP 服务是 GUI 生命周期内的服务，GUI 关闭后工具全部不可用。

### Q7：智能体返回 `{"error":"Beacon not available ..."}`？

Beacon 服务（默认 `agent_main_app`）不在线，或 endpoint 与本工具不一致。检查两侧 `--endpoint` 参数。

### Q8：`SetSourceCode` 后立刻 `GetModelJson` 拿到的是什么？

是**归一化器自动跑的**结果。`GetSourceJson` 与 `GetModelJson` 都会在 `SetSourceCode` 成功时把 LV0/LV1 顺手算好，供你检查。

### Q9：多次 `GenerateAll` 会不会污染结果？

不会。每次 `GenerateAll` 都从头重跑 17 个生成器，覆盖旧缓存。

### Q10：能不能只生成某一种语言的产物？

**当前版本不支持**。`GenerateAll` 一次把 17 个全部生成。若只需要某一种，可以从 17 个读取器里挑你要的；写入磁盘的 17 个文件可以忽略。

### Q11：运行生成的调用端 / HTML 测试页，报 `Network error` / `Failed to fetch` / `Connection refused`？

**99% 是 bridge 没开（或开了又关了）。**

排查步骤：

1. **确认 bridge 是否正在运行**：看 bridge 的终端里是否还有实时日志输出。
2. **确认 bridge 的 endpoint 与服务端一致**：两边都必须是同一字符串，例如都是 `ipc:calc_http_json`。
3. **确认 bridge 的端口与调用端一致**：默认 `8081`。调用端的 `HTTP_CALL_BASE_URL` 或 HTML 页里的 Base URL 必须写成 `http://127.0.0.1:8081/<unit>`。
4. **重启 bridge**：有时候 bridge 崩了但终端没关，看起来还“开着”。直接重启一次最省事。

> 再重复一遍：**bridge（`bridge.py` / `bridge.exe`）是转发工具，必须保持开启。**

### Q12：服务端已经跑起来了，为什么还是调不通？

服务端、bridge、调用端是**三个独立进程**，缺一不可：

```
服务端进程（必须在线）
     ▲
     │ LF_Call
bridge 进程（必须在线，前台常开）
     ▲
     │ HTTP POST
调用端进程（按需启动）
```

- 只有服务端，没有 bridge → 调用端报 Network error。
- 只有 bridge，没有服务端 → bridge 报 API not available / 超时。
- 三者都在，但没有按顺序启动 → 建议按 “服务端 → bridge → 调用端” 顺序重启一遍。

---

## 附录：三个使用姿势的一句话总结

- **GUI**：五个 Tab 从左到右点下去，看哪一步出错就往回改。
- **CLI**：`code_decl_to_json_abi [--call] 输入 输出`，扩展名决定语言，退出码决定成败。
- **智能体**：`SetSourceCode`（或 `SetModelJson`）→ `GenerateAll` → 17 个读取器按需取。

**运行阶段唯一不可忘的规则**：**bridge（`bridge.py` 或 `bridge.exe`）是转发工具，必须保持开启。**
