# code_decl_to_json_abi 完整知识库

> **定位**：本文件是 `code_decl_to_json_abi` 工具链的**唯一权威参考**。阅读本文件后，你应当能够在不查看任何源代码的情况下，正确地：
> - 通过 MCP API（22 个工具）驱动整个生成流程；
> - 理解每一项产物文件的内容与用途；
> - 判断某个 Pascal / C 函数是否会被支持；
> - 排查常见的失败场景。
>
> **承诺**：本文件的每一条结论都来自对源码的逐行核对。凡无法从源码确定的，在文末「诚实的不确定清单」中明示。
>
> **适用范围**：`code_decl_to_json_abi.lpr`、`code_decl_to_abi_json_frm.pas`、`code_decl_to_json_abi_mcp_api.pas`、`code_decl_to_json_abi_mcp_api_tool_provider_unit.pas`，以及 7 个生成器单元。
>
> **文档语言**：中文。**文件名**：英文。

---

## 目录

- [第 0 章 快速定位](#第-0-章-快速定位)
- [第 1 章 核心概念与术语](#第-1-章-核心概念与术语)
- [第 2 章 三层工作流](#第-2-章-三层工作流)
- [第 3 章 MCP API 完整参考](#第-3-章-mcp-api-完整参考)
- [第 4 章 全部 22 个工具速查](#第-4-章-全部-22-个工具速查)
- [第 5 章 UI 控件完整参考](#第-5-章-ui-控件完整参考)
- [第 6 章 7 个生成器详细契约](#第-6-章-7-个生成器详细契约)
- [第 7 章 类型系统与映射规则](#第-7-章-类型系统与映射规则)
- [第 8 章 HTTP/JSON 线协议](#第-8-章-httpjson-线协议)
- [第 9 章 错误处理与错误码](#第-9-章-错误处理与错误码)
- [第 10 章 常见陷阱与反例集](#第-10-章-常见陷阱与反例集)
- [第 11 章 AI Agent 使用规则与决策树](#第-11-章-ai-agent-使用规则与决策树)
- [第 12 章 完整使用示例](#第-12-章-完整使用示例)
- [第 13 章 诚实的不确定清单](#第-13-章-诚实的不确定清单)

---

## 第 0 章 快速定位

### 0.1 项目是什么

`code_decl_to_json_abi` 是一个**跨语言代码生成工具**。它把一段 **Pascal 单元**或 **C 头文件**作为输入，自动生成**面向 HTTP/JSON 协议的 LingoFuse 服务端 / 调用端代码**，目标语言覆盖：

- **Pascal**（服务端 + 调用端）
- **Python**（服务端 + 调用端）
- **C++**（服务端 + 调用端）
- **JavaScript**（仅调用端 + HTML 测试页）

**总计 17 个产物文件**（每个产物都配有一份 Markdown 使用文档，README 计入产物数量）。

### 0.2 三层对外接口

同一套生成能力通过三个入口暴露：

| 入口 | 文件 | 面向 |
|------|------|------|
| **GUI** | `code_decl_to_json_abi.lpr` + `code_decl_to_abi_json_frm.pas` | 人类工程师 |
| **MCP API（声明）** | `code_decl_to_json_abi_mcp_api.pas` | 仅供其他单元 `uses` |
| **MCP API（实现 + 注册）** | `code_decl_to_json_abi_mcp_api_tool_provider_unit.pas` | 供 LingoFuse 信标发现 |

**三者行为一致**：MCP 路径通过在主线程上「模拟 UI 操作」来复用 GUI 的全部逻辑。

### 0.3 5 秒速记

```
Step 1: SetSourceCode(Source, "pascal" | "c")     // 或 SetModelJson(ModelJson)
Step 2: GenerateAll()
Step 3: GetLast<Lang><Side><Artifact>()           // 从 17 个 reader 里挑
```

### 0.4 最重要的 7 条规则

1. **`Language` 参数只接受 `"pascal"` 或 `"c"`**。`python` / `cpp` / `js` 是目标语言，**不是**源语言。
2. **Step 1 之后必须调 `GenerateAll`**。否则所有 reader 返回空串。
3. **Read 是纯读**，不会触发新生成；要刷新缓存就再调一次 `GenerateAll`。
4. **一次 `SetSourceCode` 覆盖整个会话**。换目标语言不需要重调。
5. **Service 和 Call 两半必须来自同一份源文本**，不能混用。
6. **`Boolean` / `Variant` / 数组 / 记录 / 类 / 接口 / 枚举 / 集合 / 泛型 / 指针 / `Currency` / `Comp` / `TDateTime` 类型的参数会导致整条例程被静默丢弃**。
7. **`int64` / `uint64` 在 JS 客户端可能丢精度**（JS `Number` 是 IEEE-754 double）。

---

## 第 1 章 核心概念与术语

### 1.1 术语表

| 术语 | 定义 |
|------|------|
| **Source** | 输入文本：一个 Pascal 单元或一个 C 头文件 |
| **Source Language** | 源语言。**只能**是 `pascal` 或 `c` |
| **Target Language** | 目标语言。`pascal` / `python` / `cpp` / `javascript` |
| **Side** | 端别。`Service`（服务端）/ `Call`（调用端） |
| **Source JSON（LV0）** | 解析源文本得到的中间 JSON |
| **Model JSON（LV1）** | 由 Source JSON 归一化得到的模型 JSON，是生成器的唯一输入 |
| **Service** | 服务端：注册 API、解码请求、执行用户实现、编码响应 |
| **Call** | 调用端：暴露同一签名函数、序列化参数、发起远程调用 |
| **Bridge** | HTTP/JSON 与 LingoFuse 之间的转换器（`bridge.py`） |
| **MCP API** | 通过 LingoFuse 信标暴露给 agent 的 22 个工具函数 |
| **Beacon** | LingoFuse 上承载所有 tool 注册信息的应用（默认名 `agent_main_app`） |
| **Tool Provider Unit** | 把 MCP API 注册到信标的 Pascal 单元 |

### 1.2 源文本的两种合法形态

#### 1.2.1 Pascal 单元（`Language = "pascal"`）

必须是完整的 `.pas` 文件，结构：

```pascal
unit MyUnit;

interface

uses
  SysUtils, ...;

// 顶层函数/过程声明
function Add(a, b: Integer): Integer;
procedure Log(msg: string);

implementation

// 实现（会被忽略）

end.
```

**解析器关心的部分**：
- `unit` 声明（提取 `UnitName`）
- `interface` 与 `implementation` 之间的**顶层**函数 / 过程声明
- 声明前的紧邻注释（会被提取为描述）

**解析器忽略的部分**：
- `implementation` 之后的所有内容
- 类 / 记录 / 接口内部的声明（`NestLevel > 0`）
- `uses` 中的单元列表（会被记录到 `UsesList`，但不影响生成）

#### 1.2.2 C 头文件（`Language = "c"`）

必须是完整的 `.h` 文件，结构：

```c
/* MyHeader.h */
#ifndef MYHEADER_H
#define MYHEADER_H

/* 顶层函数原型 */
int Add(int a, int b);
void Log(const char* msg);

#endif /* MYHEADER_H */
```

**解析器关心的部分**：
- `#ifndef` / `#define` 守卫宏（提取 `UnitName`）
- 顶层函数原型

**解析器忽略的部分**：
- 宏定义（除守卫）
- `struct` / `enum` / `union` / `typedef`
- 全局变量声明（含 `=` 初始化）
- 函数定义（带 `{ ... }` 块）
- 函数指针参数（含 `(*...)`）

### 1.3 三大家族类型

7 个生成器都只认这三种**家族**（具体成员见第 7 章）：

- **字符串家族**
- **浮点家族**
- **整数家族**

**不属于这三家族的参数类型会导致整条例程被静默丢弃**。

### 1.4 会话状态

- 所有状态保存在主窗体实例 `code_decl_to_abi_json_form` 上。
- **不落盘**（MCP 路径按源码实现会落盘到 `<可执行文件目录>/<UnitName>/`；见第 5 章说明）。
- 无显式 reset 工具；重写 `SetSourceCode` / `SetModelJson` 会整体替换。
- 进程退出则全部丢失。

---

## 第 2 章 三层工作流

### 2.1 流程图

```
┌───────────────────────────────┐
│  Step 1: 输入                 │
│  ─────────────────────────    │
│  ① SetSourceCode(Source, Lang)│  ← 源文本 + 源语言
│  ② SetModelJson(ModelJson)    │  ← 直接喂 LV1 模型 JSON
└──────────────┬────────────────┘
               │
               ▼
┌───────────────────────────────┐
│  Step 2: 生成                 │
│  ─────────────────────────    │
│  GenerateAll()                │  ← 一次生成 17 件套，全部缓存
└──────────────┬────────────────┘
               │
               ▼
┌───────────────────────────────┐
│  Step 3: 读取                 │
│  ─────────────────────────    │
│  17 个 GetLast* reader        │  ← 逐条读取所需产物
└───────────────────────────────┘
```

### 2.2 Step 1：输入

#### 2.2.1 `SetSourceCode(Source, Language)`

| 参数 | 类型 | 必填 | 说明 |
|------|------|:----:|------|
| `Source` | `string` | 是 | 完整源文本 |
| `Language` | `string` | 是 | `"pascal"` 或 `"c"`，大小写不敏感 |

**执行动作**（在主线程上）：
1. 依据 `Language` 设置 `Sel_Lang_ComboBox.ItemIndex` 并调用 `Sel_Lang_ComboBoxChange`。
2. 把 `Source` 写入 `source_edit`。
3. 把 `MainPageControl.ActivePage` 切到 `SourceTab`。

**不解析、不生成**。

**返回**：
- `{"status":"ok"}` — 成功
- `{"error":"<message>"}` — 失败

#### 2.2.2 `SetModelJson(ModelJson)`

| 参数 | 类型 | 必填 | 说明 |
|------|------|:----:|------|
| `ModelJson` | `string` | 是 | LV1 模型 JSON（形状见 §6.6） |

**执行动作**：
1. 校验 JSON 合法性。
2. 把 `ModelJson` 写入 `model_json_edit`。
3. 把 `MainPageControl.ActivePage` 切到 `ModelJsonTab`。

**不生成**。

**返回**：
- `{"status":"ok","unit_name":"<UnitName>"}` — 成功
- `{"error":"<message>"}` — 失败

### 2.3 Step 2：`GenerateAll()`

**无参数**。

**执行动作**（按顺序在主线程上模拟点击）：

1. 若 `source_edit.Text` 非空 → 调用 `source_2_json_nex_ButtonClick`
   - 解析源文本 → 写入 `source2json_edit`
   - UI 切到 `SourceJsonTab`
2. 若 `source2json_edit.Text` 非空 → 调用 `JsonToModelButtonClick`
   - LV0 JSON → 归一化 → 写入 `model_json_edit`
   - UI 切到 `ModelJsonTab`
3. 若 `model_json_edit.Text` 非空 → 调用 `GenerateSourceButtonClick`
   - 调 7 个生成器 × 2 次（代码 + README）
   - 结果写入 17 个 `final_*_Edit`
   - 结果同时落盘到 `<可执行文件目录>/<UnitName>/`（**MCP 路径也会落盘**）
   - UI 切到 `FinalSourceTab`

**前置条件**：`source_edit` 或 `model_json_edit` 至少一个非空。

**返回**（成功）：
```json
{
  "status": "ok",
  "unit_name": "<UnitName>",
  "files": {
    "pascal_service_code":    "<UnitName>_http_json_service_unit.pas",
    "pascal_service_readme":  "<UnitName>_http_json_service_pascal.md",
    "pascal_call_code":       "<UnitName>_http_json_call_unit.pas",
    "pascal_call_readme":     "<UnitName>_http_json_call_pascal.md",
    "js_call_code":           "<UnitName>_http_json_call.js",
    "js_call_readme":         "<UnitName>_http_json_call_js.md",
    "js_test_html":           "<UnitName>_http_json_call_test.html",
    "python_service_code":    "<UnitName>_http_json_service.py",
    "python_service_readme":  "<UnitName>_http_json_service_python.md",
    "python_call_code":       "<UnitName>_http_json_call.py",
    "python_call_readme":     "<UnitName>_http_json_call_python.md",
    "cpp_service_header":     "<UnitName>_http_json_service.hpp",
    "cpp_service_impl":       "<UnitName>_http_json_service.cpp",
    "cpp_service_readme":     "<UnitName>_http_json_service_cpp.md",
    "cpp_call_header":        "<UnitName>_http_json_call.hpp",
    "cpp_call_impl":          "<UnitName>_http_json_call.cpp",
    "cpp_call_readme":        "<UnitName>_http_json_call_cpp.md"
  }
}
```

**返回**（失败）：
```json
{"error":"<message>"}
```

**失败场景**：
- `"No source text or model JSON in session. Call SetSourceCode or SetModelJson first."`
- `"Model JSON is empty. Cannot generate."`
- `"Form not available"`

### 2.4 Step 3：读取

**19 个 reader 全部无参数，全部返回 `string`**。详见 §3.3。

**关键约定**：
- **纯读**，不触发任何生成。
- 对应分支未生成过 → 返回空串 `""`。
- 每次 `GenerateAll` 都会刷新所有缓存。

### 2.5 会话行为

- **一个源，多目标**：同一次 `SetSourceCode` 之后，可以调任意 reader 组合。
- **重复 `SetSourceCode`**：整体替换源文本；先前缓存不会自动清空，但下次 `GenerateAll` 会重新填满。
- **重复 `GenerateAll`**：每次重新解析并刷新全部 17 个缓存。

---

## 第 3 章 MCP API 完整参考

### 3.1 命名规则

所有函数以 `CodeDeclToJsonAbi_` 前缀。全局唯一，便于信标发现。

### 3.2 工具函数签名（按类别）

#### 3.2.1 输入工具（2 个）

| 函数 | 签名 |
|------|------|
| `CodeDeclToJsonAbi_SetSourceCode` | `function(Source: string; Language: string): string` |
| `CodeDeclToJsonAbi_SetModelJson` | `function(ModelJson: string): string` |

#### 3.2.2 中间读取器（2 个）

| 函数 | 签名 |
|------|------|
| `CodeDeclToJsonAbi_GetSourceJson` | `function(): string` |
| `CodeDeclToJsonAbi_GetModelJson` | `function(): string` |

#### 3.2.3 生成工具（1 个）

| 函数 | 签名 |
|------|------|
| `CodeDeclToJsonAbi_GenerateAll` | `function(): string` |

#### 3.2.4 产物读取器（17 个）

全部为 `function(): string`：

1. `CodeDeclToJsonAbi_GetLastPascalServiceCode`
2. `CodeDeclToJsonAbi_GetLastPascalServiceReadme`
3. `CodeDeclToJsonAbi_GetLastPascalCallCode`
4. `CodeDeclToJsonAbi_GetLastPascalCallReadme`
5. `CodeDeclToJsonAbi_GetLastJsCallCode`
6. `CodeDeclToJsonAbi_GetLastJsCallReadme`
7. `CodeDeclToJsonAbi_GetLastJsTestHtml`
8. `CodeDeclToJsonAbi_GetLastPythonServiceCode`
9. `CodeDeclToJsonAbi_GetLastPythonServiceReadme`
10. `CodeDeclToJsonAbi_GetLastPythonCallCode`
11. `CodeDeclToJsonAbi_GetLastPythonCallReadme`
12. `CodeDeclToJsonAbi_GetLastCppServiceHeader`
13. `CodeDeclToJsonAbi_GetLastCppServiceImpl`
14. `CodeDeclToJsonAbi_GetLastCppServiceReadme`
15. `CodeDeclToJsonAbi_GetLastCppCallHeader`
16. `CodeDeclToJsonAbi_GetLastCppCallImpl`
17. `CodeDeclToJsonAbi_GetLastCppCallReadme`

### 3.3 输入工具的详细契约

#### 3.3.1 `SetSourceCode`

**成功返回**：`{"status":"ok"}`

**失败返回**：
- `{"error":"Unsupported language. Use pascal or c."}` — `Language` 非 `pascal` / `c`
- `{"error":"Form not available"}` — GUI 未初始化

**注意**：
- `Source` 为空时**不报错**，只是写入空文本。后续 `GenerateAll` 会因解析失败而报错。
- **同步机制**：`internal_call` 内部使用 `TCompute.Sync` 在主线程上执行 UI 操作。

#### 3.3.2 `SetModelJson`

**成功返回**：`{"status":"ok","unit_name":"<UnitName>"}`

**失败返回**：
- `{"error":"Empty model JSON"}`
- `{"error":"Invalid model JSON"}`
- `{"error":"Form not available"}`

### 3.4 中间读取器的详细契约

#### 3.4.1 `GetSourceJson`

**返回**：`source2json_edit.Text` 或 `""`。

- 若最近一次 Step 1 是 `SetModelJson`，**返回空串**（该路径不产生 LV0 JSON）。
- 若最近一次 Step 1 是 `SetSourceCode` 但尚未调 `GenerateAll`，仍为 `""`。
- `GenerateAll` 成功后会填入。

#### 3.4.2 `GetModelJson`

**返回**：`model_json_edit.Text` 或 `""`。

- 若最近一次 Step 1 是 `SetModelJson`，返回传入的原文。
- 若最近一次 Step 1 是 `SetSourceCode`，`GenerateAll` 成功后有值。

### 3.5 生成工具详细契约

#### 3.5.1 `GenerateAll` 的落盘副作用

**关键事实**：`GenerateAll` 内部调用的 `GenerateSourceButtonClick` **会把 17 件套写入磁盘**。落盘位置：`umlCombinePath(umlGetFilePath(ParamStr(0)), Model.UnitName)`。

- 若 `<可执行文件目录>/<UnitName>/` 不存在，会创建。
- 若目录不可写，落盘会失败但内存缓存仍会填充；MCP 返回仍为 `{"status":"ok"}`。

### 3.6 产物读取器的详细契约

每个 reader 在读取前会做两件事：

1. 把 `MainPageControl.ActivePage` 切到 `FinalSourceTab`。
2. 把 `final_source_PageControl.ActivePage` 切到对应子 `TabSheet`。

**返回值** = 对应 `final_*_Edit.Lines.Text`。

**注意**：
- 若从未 `GenerateAll`，对应 edit 为空 → 返回 `""`。
- 若 `Form not available`，返回 `""`。

### 3.7 全部 22 个工具速查表

| # | 工具名 | 类别 | 输入 | 输出 |
|---|--------|------|------|------|
| 1 | `SetSourceCode` | Step 1 | 文本 + 源语言 | 状态 JSON |
| 2 | `SetModelJson` | Step 1 | LV1 JSON | 状态 JSON |
| 3 | `GetSourceJson` | 中间读 | 无 | LV0 JSON |
| 4 | `GetModelJson` | 中间读 | 无 | LV1 JSON |
| 5 | `GenerateAll` | Step 2 | 无 | 文件清单 JSON |
| 6 | `GetLastPascalServiceCode` | Step 3 | 无 | Pascal 源码 |
| 7 | `GetLastPascalServiceReadme` | Step 3 | 无 | Markdown |
| 8 | `GetLastPascalCallCode` | Step 3 | 无 | Pascal 源码 |
| 9 | `GetLastPascalCallReadme` | Step 3 | 无 | Markdown |
| 10 | `GetLastJsCallCode` | Step 3 | 无 | JavaScript |
| 11 | `GetLastJsCallReadme` | Step 3 | 无 | Markdown |
| 12 | `GetLastJsTestHtml` | Step 3 | 无 | HTML |
| 13 | `GetLastPythonServiceCode` | Step 3 | 无 | Python 源码 |
| 14 | `GetLastPythonServiceReadme` | Step 3 | 无 | Markdown |
| 15 | `GetLastPythonCallCode` | Step 3 | 无 | Python 源码 |
| 16 | `GetLastPythonCallReadme` | Step 3 | 无 | Markdown |
| 17 | `GetLastCppServiceHeader` | Step 3 | 无 | C++ 头 |
| 18 | `GetLastCppServiceImpl` | Step 3 | 无 | C++ 实现 |
| 19 | `GetLastCppServiceReadme` | Step 3 | 无 | Markdown |
| 20 | `GetLastCppCallHeader` | Step 3 | 无 | C++ 头 |
| 21 | `GetLastCppCallImpl` | Step 3 | 无 | C++ 实现 |
| 22 | `GetLastCppCallReadme` | Step 3 | 无 | Markdown |

### 3.8 注册流程（非工具，内部）

`Execute_And_Reg_all` 一次性完成：

1. `RegisterAPIs` → 建 App + 22 次 `LF_RegisterCallEx`
2. `LF_PrepareClientEx("ipc:agent", App)`
3. `LF_PrepareDone`
4. `RegisterTools` → 向 `agent_main_app.register_agent` 注册 22 个工具的 JSON schema

**返回值**：`True` 当且仅当 22 个工具全部注册成功。

**全局变量**（可在调用前修改）：

| 变量 | 默认值 |
|------|--------|
| `MY_APP_NAME` | `"code_decl_to_json_abi_mcp_api"` |
| `MY_APP_DESC` | `"Tool provider for unit code_decl_to_json_abi_mcp_api"` |
| `IPC_ENDPOINT` | `"ipc:agent"` |
| `BEACON_APP` | `"agent_main_app"` |
| `REGISTER_API` | `"register_agent"` |
| `AGENT_LOG_API` | `"agent_log"` |
| `DEBUG_LOG` | `True` |

---

## 第 4 章 全部 22 个工具速查

（表见 §3.7，此处不再重复）

**调用模板**：

```
# 最小完整流程
SetSourceCode(MyUnitText, "pascal")
GenerateAll()
GetLastPythonServiceCode()
GetLastPythonServiceReadme()
```

```
# 直接喂模型 JSON
SetModelJson(ExistingModelJson)
GenerateAll()
GetLastCppCallHeader()
GetLastCppCallImpl()
GetLastCppCallReadme()
```

```
# 一次源文本，多次读取不同目标
SetSourceCode(MyUnitText, "pascal")
GenerateAll()
GetLastPascalServiceCode()
GetLastPythonServiceCode()
GetLastCppServiceHeader()
GetLastJsCallCode()
```

---

## 第 5 章 UI 控件完整参考

### 5.1 顶层结构

```
Tcode_decl_to_abi_json_form
├── MainPageControl: TPageControl
│   ├── WelcomeTab: TTabSheet
│   ├── SourceTab: TTabSheet
│   │   └── source_edit: TSynEdit
│   ├── SourceJsonTab: TTabSheet
│   │   └── source2json_edit: TSynEdit
│   ├── ModelJsonTab: TTabSheet
│   │   └── model_json_edit: TSynEdit
│   └── FinalSourceTab: TTabSheet
│       └── final_source_PageControl: TPageControl
│           ├── http_pas_service_TabSheet
│           │   ├── final_http_pas_service_source_Edit: TSynEdit
│           │   └── final_http_pas_service_readme_Edit: TSynEdit
│           ├── http_pas_call_TabSheet
│           │   ├── final_http_pas_call_source_Edit: TSynEdit
│           │   └── final_http_pas_call_readme_Edit: TSynEdit
│           ├── http_webjs_call_TabSheet
│           │   ├── final_http_webjs_call_source_Edit: TSynEdit
│           │   └── final_http_webjs_call_readme_Edit: TSynEdit
│           ├── http_webjs_test_TabSheet
│           │   └── final_http_webjs_test_source_Edit: TSynEdit
│           ├── http_py_service_TabSheet
│           │   ├── final_http_py_service_source_Edit: TSynEdit
│           │   └── final_http_py_service_readme_Edit: TSynEdit
│           ├── http_py_call_TabSheet
│           │   ├── final_http_py_call_source_Edit: TSynEdit
│           │   └── final_http_py_call_readme_Edit: TSynEdit
│           ├── http_cpp_service_TabSheet
│           │   ├── final_http_hpp_service_source_Edit: TSynEdit
│           │   ├── final_http_cpp_service_source_Edit: TSynEdit
│           │   └── final_http_cpp_service_readme_Edit: TSynEdit
│           └── http_cpp_call_TabSheet
│               ├── final_http_hpp_call_source_Edit: TSynEdit
│               ├── final_http_cpp_call_source_Edit: TSynEdit
│               └── final_http_cpp_call_readme_Edit: TSynEdit
├── BottomPanel: TPanel
│   └── LogMemo: TMemo
└── SysTimer: TTimer
```

### 5.2 关键字段一览

#### 5.2.1 文本编辑框（3 个）

| 字段 | 内容 |
|------|------|
| `source_edit` | 源文本 |
| `source2json_edit` | LV0 Source JSON |
| `model_json_edit` | LV1 Model JSON |

#### 5.2.2 产物编辑框（17 个）

见 §3.2.4 与 §3.7，一一对应。

#### 5.2.3 TabSheet

| 字段 | 说明 |
|------|------|
| `WelcomeTab` | 欢迎页 |
| `SourceTab` | 源文本页 |
| `SourceJsonTab` | LV0 JSON 页 |
| `ModelJsonTab` | LV1 JSON 页 |
| `FinalSourceTab` | 全部产物页 |
| `http_pas_service_TabSheet` | Pascal 服务端 |
| `http_pas_call_TabSheet` | Pascal 调用端 |
| `http_webjs_call_TabSheet` | JS 调用端 |
| `http_webjs_test_TabSheet` | JS HTML 测试页 |
| `http_py_service_TabSheet` | Python 服务端 |
| `http_py_call_TabSheet` | Python 调用端 |
| `http_cpp_service_TabSheet` | C++ 服务端 |
| `http_cpp_call_TabSheet` | C++ 调用端 |

#### 5.2.4 按钮

| 字段 | 事件 | 作用 |
|------|------|------|
| `source_2_json_nex_Button` | `source_2_json_nex_ButtonClick` | 源 → LV0 JSON |
| `JsonToModelButton` | `JsonToModelButtonClick` | LV0 JSON → LV1 JSON |
| `ModelToJsonButton` | `ModelToJsonButtonClick` | LV1 JSON → LV0 JSON（反向） |
| `BackToModelJsonButton` | `BackToModelJsonButtonClick` | 切回 ModelJsonTab |
| `JsonToPascalButton` | `JsonToPascalButtonClick` | LV0 JSON → 源代码 |
| `GenerateSourceButton` | `GenerateSourceButtonClick` | LV1 JSON → 17 件套（**有落盘**） |
| `Formater_source_Button` | `Formater_source_ButtonClick` | 源文本格式化 |
| `to_source_Button` | `to_source_ButtonClick` | 切回 SourceTab |
| `empty_unit_Button` | `empty_unit_ButtonClick` | 插入空模板 |
| `empty_unit_Button1` | `empty_unit_Button1Click` | 插入复杂测试例 |
| `Open_pascal_rule_Button` | `Open_pascal_rule_ButtonClick` | 打开 Pascal 规则文档 |
| `Open_c_rule_Button` | `Open_c_rule_ButtonClick` | 打开 C 规则文档 |

#### 5.2.5 语言选择

| 字段 | 说明 |
|------|------|
| `Sel_Lang_ComboBox` | 下拉框：`ItemIndex` = 0（未知）/ 1（Pascal）/ 2（C） |
| `Sel_Lang_ComboBoxChange` | 切换高亮器 + 更新 `current_language` |

**`current_language`** 是 **private 字段**。外部不能直接写。必须通过 `Sel_Lang_ComboBox.ItemIndex + Sel_Lang_ComboBoxChange` 间接设置。

#### 5.2.6 日志与定时器

| 字段 | 说明 |
|------|------|
| `LogMemo` | `DoStatus` 日志显示（超过 5000 行清空） |
| `SysTimer` | 刷新日志队列 + LingoFuse Sync |

### 5.3 MCP → UI 的模拟规则

每个 `internal_call_*` 都用 `TCompute.Sync` 把 UI 操作投递到主线程。以下是模拟规则表：

| MCP 工具 | UI 操作 |
|---------|---------|
| `SetSourceCode` | 设置 `Sel_Lang_ComboBox.ItemIndex` → 调 `Sel_Lang_ComboBoxChange` → 写 `source_edit.Text` → 切到 `SourceTab` |
| `SetModelJson` | 校验 JSON → 写 `model_json_edit.Text` → 切到 `ModelJsonTab` |
| `GetSourceJson` | 读 `source2json_edit.Text` |
| `GetModelJson` | 读 `model_json_edit.Text` |
| `GenerateAll` | 有源 → 调 `source_2_json_nex_ButtonClick`；有 LV0 → 调 `JsonToModelButtonClick`；有 LV1 → 调 `GenerateSourceButtonClick`；最后切到 `FinalSourceTab` |
| 全部 17 个 reader | 切到 `FinalSourceTab` → 切到对应子 `TabSheet` → 读对应 `final_*_Edit.Lines.Text` |

### 5.4 落盘位置

`GenerateSourceButtonClick` 中：

```pascal
app_dir.Text := umlCombinePath(umlGetFilePath(ParamStr(0)), func_model.UnitName);
umlCreateDirectory(app_dir.Text);
```

即产物写到 `<可执行文件目录>/<UnitName>/`。**MCP 路径也会落盘**（因为内部就是调用这个事件）。

### 5.5 落盘文件名

由 `SaveCode(fn)` / `SaveSynEditCode(edit, fn)` 指定：

| 调用 | 文件名 |
|------|--------|
| `SaveSynEditCode(source_edit, 'source.pas')` | `source.pas`（源，仅当非空） |
| `SaveSynEditCode(source_edit, 'source.h')` | `source.h`（C 源，仅当非空） |
| `SaveSynEditCode(source2json_edit, 'source.json')` | `source.json`（仅当非空） |
| `SaveSynEditCode(model_json_edit, 'source_model.json')` | `source_model.json`（仅当非空） |
| `SaveCode(func_model.UnitName + '_http_json_service_unit.pas')` | Pascal 服务端 |
| `SaveCode(func_model.UnitName + '_http_json_service_pascal.md')` | Pascal 服务端 README |
| `SaveCode(func_model.UnitName + '_http_json_call_unit.pas')` | Pascal 调用端 |
| `SaveCode(func_model.UnitName + '_http_json_call_pascal.md')` | Pascal 调用端 README |
| `SaveCode(func_model.UnitName + '_http_json_call.js')` | JS 调用端 |
| `SaveCode(func_model.UnitName + '_http_json_call_js.md')` | JS 调用端 README |
| `SaveCode(func_model.UnitName + '_http_json_call_test.html')` | JS 测试页 |
| `SaveCode(func_model.UnitName + '_http_json_service.py')` | Python 服务端 |
| `SaveCode(func_model.UnitName + '_http_json_service_python.md')` | Python 服务端 README |
| `SaveCode(func_model.UnitName + '_http_json_call.py')` | Python 调用端 |
| `SaveCode(func_model.UnitName + '_http_json_call_python.md')` | Python 调用端 README |
| `SaveCode(func_model.UnitName + '_http_json_service.hpp')` | C++ 服务端头 |
| `SaveCode(func_model.UnitName + '_http_json_service.cpp')` | C++ 服务端实现 |
| `SaveCode(func_model.UnitName + '_http_json_service_cpp.md')` | C++ 服务端 README |
| `SaveCode(func_model.UnitName + '_http_json_call.hpp')` | C++ 调用端头 |
| `SaveCode(func_model.UnitName + '_http_json_call.cpp')` | C++ 调用端实现 |
| `SaveCode(func_model.UnitName + '_http_json_call_cpp.md')` | C++ 调用端 README |

---

## 第 6 章 7 个生成器详细契约

### 6.1 通用契约（7 个生成器共享）

| 项 | 约定 |
|----|------|
| **输入** | `TPascal_Func_Model`，必须 `Typ_Normalize_Func = tnf_ABI` |
| **输出** | `TPascalStringList`（行列表），调用方 `DisposeObject` |
| **空模型** | `Model = nil` 或 `Model.UnitName` 为空 → 返回 `nil` |
| **不支持的例程** | 静默丢弃，仅 `DoStatus` 打印一条日志（当 `GenerateCode_LogEnabled=True`） |
| **重载** | 同名重载按顺序加 `_1`、`_2` 后缀 |

### 6.2 名字规范化

`MakeApiName(FuncName)` 把 `FuncName` 中的下列字符替换为 `_`：

- 空格、制表符
- `.` `/` `\` `@` `:` `#` `?` `&` `=` `+`

**注意**：`-` 不替换。若源函数名含 `-`，生成的 JS/C++ 标识符会语法错误。

### 6.3 文件名规则

所有产物名以 `Model.UnitName` 为前缀（`UnitName` 也会先做 `MakeApiName` 规范化）。

| 生成器 | 输出文件 |
|--------|---------|
| Pascal 服务端 | `<U>_http_json_service_unit.pas` + `<U>_http_json_service_pascal.md` |
| Pascal 调用端 | `<U>_http_json_call_unit.pas` + `<U>_http_json_call_pascal.md` |
| JS 调用端 | `<U>_http_json_call.js` + `<U>_http_json_call_js.md` + `<U>_http_json_call_test.html` |
| Python 服务端 | `<U>_http_json_service.py` + `<U>_http_json_service_python.md` |
| Python 调用端 | `<U>_http_json_call.py` + `<U>_http_json_call_python.md` |
| C++ 服务端 | `<U>_http_json_service.hpp` + `<U>_http_json_service.cpp` + `<U>_http_json_service_cpp.md` |
| C++ 调用端 | `<U>_http_json_call.hpp` + `<U>_http_json_call.cpp` + `<U>_http_json_call_cpp.md` |

其中 `<U>` = 规范化后的 `UnitName`。

### 6.4 逐生成器细节

#### 6.4.1 Pascal 服务端（`http_pas_abi_service_generator_tool`）

**输出结构**：
- 单元名：`<U>_http_json_service_unit`
- 接口：
  - `HTTP_SERVICE_APP_NAME` / `HTTP_SERVICE_APP_DESC`（可改）
  - `DEBUG_LOG: Boolean`（可改）
  - `RegisterAllHTTPJsonAPIs(App: TAppHnd___)`
  - `CreateAndRegisterHTTPJsonApp: TAppHnd___`
  - `function internal_call_<Api>(...): ...;` × N（**stub，需要用户填**）
- 实现：
  - JSON 访问辅助（`_Json_Get_Int64_ByIndex` 等）
  - cdecl 回调（`Callback_<Api>`）
  - 注册函数

**依赖**（生成的单元需要）：
- `SysUtils, Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib, Z.Json, lingofuse_import`

**用户需要做的事**：
1. 在 `implementation` 段的 `uses` 中加入真正的实现单元。
2. 填每个 `internal_call_<Api>` 的函数体。
3. 宿主程序按标准 LingoFuse 服务流程启动。

#### 6.4.2 Pascal 调用端（`http_pas_abi_call_generator_tool`）

**输出结构**：
- 单元名：`<U>_http_json_call_unit`
- 接口：
  - `EHTTPCallError = class(Exception)`
  - `HTTP_CALL_BASE_URL: string`（可改）
  - `function <Api>(...): ...;` × N
- 实现：每个函数走 `LFHttpPost` → 校验 `body.code` → 返回 `body.result`

**依赖**：
- `SysUtils, Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib, Z.Json, lingofuse_import, lf_http_bridge_client`

**用户需要做的事**：
1. 在程序启动时准备 LingoFuse（`LF_ResetPrepare` / `LF_PrepareClient` / `LF_PrepareDone`）。
2. 设置 `HTTP_CALL_BASE_URL`。
3. 直接调用生成的自由函数。

#### 6.4.3 JS 调用端（`http_js_abi_call_generator_tool`）

**输出 3 个文件**：

1. `<U>_http_json_call.js` — 独立 IIFE 库
   - 挂在 `window.<U>Api`（或 `globalThis.<U>Api`）
   - 成员：`baseUrl` / `getBaseUrl()` / `setBaseUrl(url)` / `Error` / 每个 API 一个 `async` 函数
   - 无第三方依赖（仅 `fetch` / `Promise` / `async-await`）

2. `<U>_http_json_call_js.md` — README

3. `<U>_http_json_call_test.html` — 自包含测试页
   - 内嵌 JS 库
   - 每个 API 一个测试卡片：参数输入框 + 按钮 + 结果区

**JS 精度警告**：`int64` / `uint64` 参数和返回值会在 JSDoc 中打上 `@warning`。

#### 6.4.4 Python 服务端（`http_py_abi_service_generator_tool`）

**输出结构**：
- 依赖：`lingofuse` Python 包
- 接口：
  - `HTTP_SERVICE_APP_NAME` / `HTTP_SERVICE_APP_DESC` / `HTTP_SERVICE_ENDPOINT`（可改）
  - `DEBUG_LOG: bool`（可改）
  - `register_all_http_json_apis(app)`
  - `create_and_register_http_json_app()`
  - `internal_call_<Api>(...)` × N（stub）
  - `main()` — 含信号处理与干净关闭

**用户需要做的事**：
1. 填每个 `internal_call_<Api>`。
2. 运行 `python3 <U>_http_json_service.py`。
3. 用相同 `--endpoint` 启动 `bridge.py`。

#### 6.4.5 Python 调用端（`http_py_abi_call_generator_tool`）

**输出结构**：
- 依赖：`requests`
- 接口：
  - `HTTP_CALL_BASE_URL: str`
  - `HTTP_CALL_TIMEOUT: float`（默认 30.0）
  - `DEBUG_LOG: bool`（默认 False）
  - `HTTPCallError`
  - 每个 API 一个函数
  - `_call_api(api_name, args)` — 内部统一入口

**用户需要做的事**：
1. `pip install requests`
2. `import <U>_http_json_call as api`
3. `api.HTTP_CALL_BASE_URL = "http://.../<app>"`
4. 调用生成的函数

#### 6.4.6 C++ 服务端（`http_cpp_abi_service_generator_tool`）

**输出 3 个文件**：

1. `<U>_http_json_service.hpp`
   - 依赖：`<cstdint>` `<string>` `LingoFuse.hpp`
   - 命名空间：`<u>`（`U` 小写）
   - 成员：`HTTP_SERVICE_APP_NAME` 等常量、`internal_call_<Api>` × N、`register_all_http_json_apis` / `create_and_register_http_json_app` / `run_service`
2. `<U>_http_json_service.cpp`
   - 实现：stub 定义、cdecl 回调、注册、`main()`
   - 依赖：`LingoFuse.hpp` / `lf_io.hpp` / `json.hpp`
3. `<U>_http_json_service_cpp.md`

**用户需要做的事**：
1. 填每个 `internal_call_<Api>`。
2. `g++ -std=c++17 ... LingoFuse.c -o service -pthread -ldl`
3. 启动服务，再用相同 endpoint 启动 bridge。

#### 6.4.7 C++ 调用端（`http_cpp_abi_call_generator_tool`）

**输出 3 个文件**：

1. `<U>_http_json_call.hpp`
   - 依赖：`<cstdint>` `<stdexcept>` `<string>`
   - 命名空间：`<u>`
   - 成员：
     - `HTTP_BRIDGE_APP_NAME`（默认 `__lf_http_bridge__`）
     - `HTTP_BRIDGE_API_NAME`（默认 `__lf_outbound_post__`）
     - `HTTP_CALL_TIMEOUT_MS`（默认 60000）
     - `HTTP_CALL_BASE_URL`（默认 `http://127.0.0.1:8081/<U>`）
     - `HTTP_CALL_DEFAULT_TIMEOUT_S`（默认 25.0）
     - `HTTPCallError` 类
     - `<Api>` × N
2. `<U>_http_json_call.cpp`
   - 内部统一入口 `_lf_http_post(url, body, timeout)`
3. `<U>_http_json_call_cpp.md`

**用户需要做的事**：
1. 准备 LingoFuse（`LibraryLoader` / `resetPrepare` / `prepareClient` / `prepareDone`）。
2. 设置 `HTTP_CALL_BASE_URL`。
3. 调用生成函数。

### 6.5 `internal_call_<Api>` stub 的形状

每个 stub 是用户需要填的地方。原样复制：

**Pascal**：
```pascal
function internal_call_Foo_Foo(a: Int64; b: string): Int64;
begin
  // TODO: call the real function
  Result := 0;
end;
```

**Python**：
```python
def internal_call_Foo(a: int, b: str) -> int:
    """..."""
    # TODO: call the real function
    return 0
```

**C++**：
```cpp
std::int64_t internal_call_Foo(std::int64_t a, std::string b) {
    // TODO: call the real function
    return 0;
}
```

### 6.6 LV1 Model JSON 形状

`GenerateAll` 实际消费的是这个 JSON。若你通过 `SetModelJson` 直接喂入，必须包含以下字段：

```json
{
  "UnitName": "MyUnit",
  "Functions": [
    {
      "Name": "Add",
      "IsFunction": true,
      "Comment": "Adds two numbers",
      "ReturnType": "int64",
      "Params": [
        {"Name": "a", "Typ": "Integer", "PascalType": "int64", "Description": "First operand"},
        {"Name": "b", "Typ": "Integer", "PascalType": "int64", "Description": "Second operand"}
      ]
    }
  ]
}
```

**关键点**：
- `UnitName` 必填。
- `Functions` 数组里每个元素的 `Name` / `IsFunction` / `Params` / `ReturnType` 必填。
- `PascalType` 决定类型家族判定（见第 7 章）。
- `Description` 用于 README。

### 6.7 生成器与 GUI 事件的对应

| GUI 事件 | 调用的生成器 |
|----------|-------------|
| `source_2_json_nex_ButtonClick` | 无（仅做解析） |
| `JsonToModelButtonClick` | 无（仅做归一化） |
| `JsonToPascalButtonClick` | `tpascal_func_decl_tool.decl_to_pascal` / `decl_to_c` |
| `Formater_source_ButtonClick` | 同上 |
| `GenerateSourceButtonClick` | **全部 7 个生成器 × 2（代码 + README）** |

---

## 第 7 章 类型系统与映射规则

### 7.1 三大家族

#### 7.1.1 字符串家族

| 类型名（大小写不敏感） |
|------------------------|
| `string` / `ansistring` / `unicodestring` |
| `tpascalstring` / `tupascalstring` / `tp_string` |
| `pchar` / `pansichar` / `pwidechar` |
| `u_string`（**仅 JS 生成器识别**；Pascal/Python/C++ 生成器不识别） |

#### 7.1.2 浮点家族

| 类型名 |
|--------|
| `double` / `single` / `extended` / `real` |

#### 7.1.3 整数家族

| 类型名 |
|--------|
| `integer` / `longint` / `int64` |
| `cardinal` / `dword` / `longword` / `uint64` |
| `word` / `smallint` / `byte` |

### 7.2 目标语言映射表

| ABI 家族 | Pascal | Python | C++ | JavaScript |
|----------|--------|--------|-----|-----------|
| 字符串 | `string` | `str` | `std::string` | `string` |
| 浮点 | `Double` / `Single` / `Extended` / `Real`（各自保留） | `float` | `double` | `number` |
| 整数 | 各自保留（`Integer` / `Int64` / ...） | `int` | `std::int64_t`（全部收窄） | `number` |

**关键差异**：
- **Pascal** 保留原始宽度。
- **Python** 用 `int`（无界），标注仅供参考。
- **C++** 全部整数收窄到 `std::int64_t`，全部浮点收窄到 `double`。
- **JavaScript** 全部整数和浮点收窄到 `number`（IEEE-754 double），**有精度风险**。

### 7.3 不支持的类型

以下类型会导致**整条例程被静默丢弃**：

- `Boolean` / `WordBool` / `LongBool`
- `Variant` / `OleVariant`
- 数组、记录、类、接口
- 枚举、集合、泛型
- 指针、函数指针
- `Currency` / `Comp` / `TDateTime`

**Workaround**：把复杂值序列化为 `string` 再传递。

### 7.4 JSON 线上类型

HTTP/JSON 协议比 ABI 二进制协议少了类型信息：

| ABI 家族 | JSON 线上类型 |
|----------|-------------|
| 字符串 | `string` |
| 浮点 | `number` |
| 整数 | `number` |

因此：
- JSON 客户端无法通过字节区分 `Integer` 和 `Int64`。
- 大整数的精度由客户端 JSON 解析器决定。
- 服务端按声明的 Pascal 类型反序列化；若 JSON 数字超出目标类型范围，会**静默截断**。

### 7.5 数值精度限制速查

| 场景 | 限制 |
|------|------|
| JS `Number` 精确表示整数范围 | ±2^53 − 1 |
| `int64` 最大值 | 9223372036854775807 ≈ 9.2×10^18 |
| `uint64` 最大值 | 18446744073709551615 ≈ 1.8×10^19 |
| JSON 数字（Python `json`） | 无界 int，或有界 float |
| JSON 数字（JS `JSON.parse`） | IEEE-754 double |

**建议**：在 JS 客户端处理 `int64` / `uint64` 时，让服务端返回字符串。

---

## 第 8 章 HTTP/JSON 线协议

### 8.1 URL 组成

#### 8.1.1 调用端 → 桥

```
HTTP_CALL_BASE_URL + "/" + <api-name>
```

- `HTTP_CALL_BASE_URL` 默认：`http://127.0.0.1:8081/<U>`
- 用户可在调用端初始化后修改

#### 8.1.2 桥 → 服务端

桥把 `/<app>/<api>` 映射为 LingoFuse 调用 `LF_Call(<app>, <api>)`。

### 8.2 请求格式

#### 8.2.1 调用端 → 桥（LingoFuse 调用）

```
LF_Call("__lf_http_bridge__", <bridge_request>)
```

`<bridge_request>` 是 JSON：

```json
{
  "url":     "http://.../<api>",
  "method":  "POST",
  "headers": { "Content-Type": "application/json; charset=utf-8" },
  "body":    { "args": [v1, v2, ...] },
  "timeout": 25.0
}
```

#### 8.2.2 桥 → 服务端（HTTP POST）

```http
POST /<app>/<api> HTTP/1.1
Content-Type: application/json; charset=utf-8
Content-Length: ...

{"args": [v1, v2, ...]}
```

### 8.3 响应格式

#### 8.3.1 服务端 → 桥

```json
{"code": 0, "result": <value>}     // 成功
{"code": -1, "error": "<message>"} // 失败
```

#### 8.3.2 桥 → 调用端（envelope）

```json
{
  "status_code": 200,
  "headers": { ... },
  "body": { "code": 0, "result": <value> }
}
```

#### 8.3.3 调用端解包

读 `body` 字段，检查 `body.code`：

- `body.code = 0` → 返回 `body.result`
- `body.code <> 0` → 抛异常

### 8.4 参数语义

#### 8.4.1 位置参数（推荐）

```json
{"args": [v1, v2, v3]}
```

- 数组第 `i` 项映射到原函数第 `i` 个参数
- 参数个数不足时，缺失参数用类型默认值（`0` / `0.0` / `""`）

#### 8.4.2 命名参数（备选）

```json
{"param1": v1, "param2": v2}
```

- 与原函数参数名匹配（**大小写敏感**）
- **仅在 `args` 不存在时生效**

#### 8.4.3 优先级

`args` 存在则**完全忽略**命名参数。

### 8.5 字符编码

- 请求和响应都是 **UTF-8**
- 序列化策略：`ensure_ascii=False`
- 桥在转发前会剥离 LingoFuse 字符串尾部的 `\0`

### 8.6 HTTP 方法

桥只接受 **`POST`**（其他方法被拒绝）。

---

## 第 9 章 错误处理与错误码

### 9.1 工具链错误 JSON 形状

#### 9.1.1 输入/生成工具错误

```json
{"error":"<message>"}
```

#### 9.1.2 服务端/桥错误

```json
{"code": -N, "error": "<message>"}
```

### 9.2 全部已知错误消息

| 消息 | 触发 |
|------|------|
| `Unsupported language. Use pascal or c.` | `Language` 非 `pascal` / `c` |
| `Empty model JSON` | `SetModelJson("")` |
| `Invalid model JSON` | `SetModelJson(非法 JSON)` |
| `Form not available` | 主窗体未创建 |
| `No source text or model JSON in session. Call SetSourceCode or SetModelJson first.` | `GenerateAll` 在 Step 1 之前调用 |
| `Model JSON is empty. Cannot generate.` | `model_json_edit` 为空 |

### 9.3 服务/桥错误码

| code | 含义 | 常见 `http_status` |
|:----:|------|:------------------:|
| `0` | 成功 | 200 |
| `-1` | 远程调用失败（服务端异常、网络错误、超时） | 200（服务端异常）/ 0（网络错误） |
| `-2` | 请求形状错误（URL 路径无法解析） | 400 |
| `-3` | 桥预检失败（桥没有发现目标 API） | 200 |

### 9.4 各目标语言的异常类型

| 目标 | 异常类 | 字段 |
|------|--------|------|
| Pascal | `EHTTPCallError` | `.Message`（无 `.code` 字段） |
| Python | `HTTPCallError` | `.code` / `.http_status` |
| C++ | `HTTPCallError` | `.code` / `.http_status` |
| JavaScript | `LFHttpCallError` | `.code` / `.httpStatus` |

### 9.5 排查流程

1. **检查 Step 1 是否成功**（返回 `{"status":"ok"}`）。
2. **检查 `GenerateAll` 是否成功**。
3. **检查 reader 返回值**（空串说明未生成）。
4. **检查 LingoFuse 连接**（`Execute_And_Reg_all` 的返回值）。
5. **检查 `LogMemo`**（所有 `DoStatus` 输出）。

### 9.6 桥预检失败（code = -3）处理

`bridge.py` 默认会检查 `check_api`，依赖广播缓存，可能滞后 3 秒。建议：

- 桥启动时加 `--no-precheck`
- 或服务端启动后等 3 秒再调用
- 或客户端捕获 `code = -3` 后延迟重试

---

## 第 10 章 常见陷阱与反例集

### 10.1 输入阶段陷阱

| 反例 | 正确做法 |
|------|---------|
| `SetSourceCode(Text, "python")` | `SetSourceCode(Text, "pascal")` + 读 Python reader |
| `SetSourceCode(Text, "cpp")` | `SetSourceCode(Text, "c")` + 读 C++ reader |
| 直接 `GenerateAll` | 先 `SetSourceCode` 或 `SetModelJson` |
| `SetSourceCode` 后直接读 | 中间必须 `GenerateAll` |
| `SetModelJson(手写 JSON)` 不带 `UnitName` | 必须含 `UnitName` / `Functions` |

### 10.2 生成阶段陷阱

| 反例 | 正确做法 |
|------|---------|
| 以为只能 `GenerateAll` 一次 | 可以多次；每次刷新缓存 |
| `SetSourceCode(A)` → 读 → `SetSourceCode(B)` → 读 | 后一次会覆盖前一次；一次会话只应有一个源 |
| 期望 MCP 路径不落盘 | 实际会落盘到 `<exe目录>/<UnitName>/` |
| 假设目录可写 | 无写权限时落盘失败但内存缓存仍有效 |

### 10.3 读取阶段陷阱

| 反例 | 正确做法 |
|------|---------|
| 期望 reader 触发生成 | reader 只读缓存 |
| 生成 Service 后读 Call reader | 会得空串；读对应分支 |
| `SetModelJson` 后读 `GetSourceJson` | 得空串；该路径无 LV0 |

### 10.4 类型阶段陷阱

| 反例 | 正确做法 |
|------|---------|
| 源单元里有 `Boolean` 参数 | 改成 `Integer`（0/1）或 `string` |
| 源单元里有数组参数 | 序列化成 `string` |
| 期望 `int64` 在 JS 端无损 | JS `Number` 只能精确到 2^53；让服务端返回字符串 |
| 期望 `Extended` 跨平台一致 | 按 `double` 处理 |

### 10.5 会话阶段陷阱

| 反例 | 正确做法 |
|------|---------|
| 期望有 reset 工具 | 没有；重新 `SetSourceCode` / `SetModelJson` |
| 多线程并发 `GenerateAll` | 串行化；内部 UI 操作不保证并发安全 |
| 期望进程退出后状态保留 | 内存态，进程退出即丢失 |

### 10.6 UI 阶段陷阱

| 反例 | 正确做法 |
|------|---------|
| 直接写 `current_language` | 用 `Sel_Lang_ComboBox.ItemIndex + Sel_Lang_ComboBoxChange` |
| 期望 `*_ButtonClick` 不产生日志 | 会 `DoStatus` 到 `LogMemo` |
| 期望 `LogMemo` 无限保留 | 超过 5000 行清空 |

### 10.7 完整反例清单

| # | 反例 | 后果 | 修正 |
|---|------|------|------|
| 1 | `Language='python'` | 返回 error | 用 `pascal` / `c` |
| 2 | 跳过 `GenerateAll` | reader 空串 | 先 `GenerateAll` |
| 3 | `SetSourceCode` 两次不 `GenerateAll` | 缓存未更新 | 重新 `GenerateAll` |
| 4 | Service / Call 混用 | 线上协议不匹配 | 同源生成 |
| 5 | 有 `Boolean` 参数 | 整条例程丢弃 | 改类型 |
| 6 | JS 处理 `int64` | 精度丢失 | 服务端返回字符串 |
| 7 | 忘记桥 `--no-precheck` | 首调 `code = -3` | 加 `--no-precheck` |
| 8 | 未准备 LingoFuse | 调用端初始化失败 | `LF_PrepareClient` + `LF_PrepareDone` |
| 9 | 桥 endpoint 与服务端不匹配 | `code = -3` | 检查 `--endpoint` |
| 10 | 期望空源文本报错 | 实际静默写入 | 自行校验输入 |

---

## 第 11 章 AI Agent 使用规则与决策树

### 11.1 十条使用规则

1. **`Language` 只传 `pascal` 或 `c`**。传其它一律返回错误。
2. **Step 1 之后必须调 `GenerateAll`**，然后才能调 reader。
3. **Read 是纯读**。要刷新就再 `GenerateAll`。
4. **一个会话一次 `SetSourceCode` 即可**。换目标语言不换源。
5. **Service / Call 必须同源**。
6. **有 `int64` / `uint64` 参数或返回值时提醒用户 JS 精度问题**。
7. **不支持的例程会被静默丢弃**，让用户看 `LogMemo` 或检查产物。
8. **失败时先看 `LogMemo`**，再看 MCP 返回的 `error`。
9. **MCP 路径会落盘**到 `<exe目录>/<UnitName>/`。
10. **不确定时先跑最小示例**。

### 11.2 决策树

```
用户想要什么？
├── "从 Pascal 单元生成代码"
│   ├── 目标 Pascal 服务端 → SetSourceCode(pas) → GenAll → GetLastPascalServiceCode
│   ├── 目标 Pascal 调用端 → SetSourceCode(pas) → GenAll → GetLastPascalCallCode
│   ├── 目标 Python 服务端 → SetSourceCode(pas) → GenAll → GetLastPythonServiceCode
│   ├── 目标 Python 调用端 → SetSourceCode(pas) → GenAll → GetLastPythonCallCode
│   ├── 目标 C++ 服务端  → SetSourceCode(pas) → GenAll → GetLastCppServiceHeader + Impl
│   ├── 目标 C++ 调用端  → SetSourceCode(pas) → GenAll → GetLastCppCallHeader + Impl
│   └── 目标 JS 调用端   → SetSourceCode(pas) → GenAll → GetLastJsCallCode + Html
└── "从 C 头文件生成代码"
    └── 同上，Language 传 "c"
```

### 11.3 检查清单（调用前）

- [ ] 目标语言？（pascal / python / cpp / js）
- [ ] 服务端还是调用端？
- [ ] 源文本是 Pascal 还是 C？
- [ ] 所有参数类型是否都支持？
- [ ] 是否有 `Boolean` / `Variant` / 数组 / 记录参数？（→ 会被丢弃）
- [ ] 是否有 `int64` 参数或返回值？（→ JS 精度问题）

### 11.4 检查清单（调用后）

- [ ] `SetSourceCode` / `SetModelJson` 返回 `{"status":"ok"}`？
- [ ] `GenerateAll` 返回 `{"status":"ok"}`？
- [ ] 所需 reader 返回非空字符串？
- [ ] 若为空，是否调错分支（Service / Call）？
- [ ] `LogMemo` 是否有丢弃例程的警告？

### 11.5 输出文件命名速记

```
<UnitName>_http_json_<side>.<ext>

side ∈ {service, call}
ext  ∈ {pas, py, hpp, cpp, js, html, md}
```

### 11.6 常见问题快速回答

**Q: 我该用 `SetSourceCode` 还是 `SetModelJson`？**
A: 有源文本用 `SetSourceCode`；有 LV1 JSON（比如从别处生成来的）用 `SetModelJson`。绝大多数场景用 `SetSourceCode`。

**Q: 生成产物在哪？**
A: 内存里（reader 返回）+ 磁盘上（`<exe目录>/<UnitName>/`）。

**Q: 为什么 reader 返回空串？**
A: 三个原因之一：① 未 `GenerateAll`；② 调错分支；③ 源文本为空。

**Q: 为什么某个函数没有出现在生成结果里？**
A: 它含有不支持的类型，被静默丢弃。查 `LogMemo`。

**Q: 我需要为每种目标语言调一次 `SetSourceCode` 吗？**
A: 不需要。一次 `SetSourceCode` 之后，`GenerateAll` 会一次生成全部 17 件套。可以随意读。

---

## 第 12 章 完整使用示例

### 12.1 最小完整流程（Pascal 源 → Python 服务端）

**输入**（Pascal 单元）：

```pascal
unit Calculator;

interface

// Adds two numbers
function Add(a, b: Integer): Integer;

// Subtracts b from a
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

**调用序列**：

```
1. CodeDeclToJsonAbi_SetSourceCode(<上面的文本>, "pascal")
   → {"status":"ok"}

2. CodeDeclToJsonAbi_GenerateAll()
   → {"status":"ok","unit_name":"Calculator","files":{...}}

3. CodeDeclToJsonAbi_GetLastPythonServiceCode()
   → Python 模块源码

4. CodeDeclToJsonAbi_GetLastPythonServiceReadme()
   → Markdown 使用文档
```

### 12.2 C 源 → C++ 调用端

**输入**（C 头文件）：

```c
/* Math.h */
#ifndef MATH_H
#define MATH_H

int square(int x);
double sqrt_of(double x);

#endif
```

**调用序列**：

```
1. SetSourceCode(<上面的文本>, "c")
2. GenerateAll()
3. GetLastCppCallHeader()
4. GetLastCppCallImpl()
5. GetLastCppCallReadme()
```

### 12.3 一源多目标

```
1. SetSourceCode(MyUnitText, "pascal")
2. GenerateAll()

// 读任意目标，全部来自同一源
3. GetLastPascalServiceCode()
4. GetLastPythonServiceCode()
5. GetLastCppServiceHeader()
6. GetLastCppServiceImpl()
7. GetLastJsCallCode()
8. GetLastJsTestHtml()
```

**不需要**重调 `SetSourceCode`。

### 12.4 直接使用已有 Model JSON

```
1. SetModelJson('{"UnitName":"X","Functions":[...]}')
   → {"status":"ok","unit_name":"X"}
2. GenerateAll()
3. GetLastPascalCallCode()
```

### 12.5 排查失败

```
SetSourceCode(Text, "pascal")
GenerateAll()
// 返回 {"error":"Model JSON is empty. Cannot generate."}
// ↓ 说明源文本解析失败
GetSourceJson()
// 若为空 → 源文本本身有问题
// 若不为空 → LV0 到 LV1 归一化失败（少见）
```

### 12.6 用户手册（GUI）流程

1. 打开程序。
2. 顶部下拉选 `Pascal` 或 `C`。
3. `Source` 页粘源文本。
4. 点 `Source → JSON`。
5. 点 `JSON → Model`。
6. 点 `Generate Source`。
7. 在 `Final Source` 页各 TabSheet 查看/复制产物。
8. 产物同时被写到 `<exe目录>/<UnitName>/`。

---

## 第 13 章 诚实的不确定清单

以下条目无法从现有源码完全确定，使用前请回查源码或询问人类。

1. **`GenerateAll` 在无写权限目录下的落盘行为**
   - 源码调用 `SaveCode` / `SaveSynEditCode`，内部走 `TPascalStringList.SaveToFile`。
   - **不确定**：写入失败时是否有异常被吞掉；MCP 返回是否会受影响。
   - **建议**：只依赖内存缓存（reader 返回值），不要依赖磁盘。

2. **`GenerateSourceButtonClick` 中异常传播到 MCP 的路径**
   - 源码的按钮事件没有 `try...except` 包裹。
   - **不确定**：异常是否会被 `Callback_*` 捕获并转为 `{"error":...}`。
   - **推测**：会（因为 `Callback_*` 有 `except on E: Exception`），但异常消息可能不完整。

3. **`Sel_Lang_ComboBoxChange` 在 `ItemIndex = 0` 时的行为**
   - 源码分支 `else` 把 `source_edit.Highlighter` 设为 `AnyHighlighter`，`current_language` 设为 `slUnknown`。
   - **不确定**：设为 `slUnknown` 后再调 `source_2_json_nex_ButtonClick` 会怎样。
   - **推测**：会报 `"不支持语言."` 并 exit。

4. **多个 `TFuncDeclList` 同时使用时的状态共享**
   - `tpascal_func_decl_tool` 内部是否使用全局状态。
   - **不确定**：并发调用是否安全。

5. **`MakeApiName` 对 `-` 的处理**
   - 源码不替换 `-`。
   - **不确定**：这是有意的（因为 Pascal 函数名不含 `-`）还是遗漏。
   - **推测**：有意。

6. **`empty_unit_Button1Click` 插入的复杂测试例是否全部能被解析**
   - 该示例包含多种边缘语法（泛型、函数指针、嵌套类型等）。
   - **不确定**：是否每种语法都被 `Z.Pascal_Func_Tool` 正确解析。
   - **建议**：当作**解析器压力测试**而非生成器测试。

7. **`GetLastJsTestHtml` 输出的 HTML 是否可直接双击打开运行**
   - 生成的 HTML 内嵌了 JS 库，理论上可离线运行。
   - **不确定**：`file://` 协议下的 CORS 行为。
   - **推测**：对于 `http://127.0.0.1:8081` 的请求会触发跨源；建议用本地 HTTP 服务器伺服。

8. **C++ 调用端的 `_lf_http_post` 内部是否线程安全**
   - 源码使用 `lingofuse::DataHandle` + `lingofuse::call`。
   - **不确定**：并发调用时是否有共享状态竞争。
   - **推测**：`LF_Call` 是线程安全的（参见 LingoFuse 文档）。

9. **`HTTP_CALL_DEFAULT_TIMEOUT_S` 与 `HTTP_CALL_TIMEOUT_MS` 的关系**
   - 源码中 `HTTP_CALL_DEFAULT_TIMEOUT_S = 25.0`，`HTTP_CALL_TIMEOUT_MS = 60000`。
   - **不确定**：`60000 ms` 是 LingoFuse 往返超时，`25.0 s` 是 HTTP 请求超时；两者关系需手动保持一致。
   - **建议**：确保 `HTTP_CALL_TIMEOUT_MS > HTTP_CALL_DEFAULT_TIMEOUT_S * 1000`。

10. **`LogMemo` 超过 5000 行时的清空策略**
    - 源码 `if LogMemo.Lines.Count > 5000 then LogMemo.Lines.Clear;`。
    - **不确定**：是否会在日志暴增时产生性能问题。

11. **`SysTimer` 的间隔**
    - 源码里没有直接给出 `Interval`。
    - **不确定**：具体值。
    - **推测**：100–500 ms 之间。

12. **`Callback_*` 是否全部正确注册**
    - 源码有 22 个 `Callback_*` 函数。
    - **不确定**：`RegisterAPIs` 里是否有遗漏或重复。
    - **推测**：与 `RegisterTools` 中的 22 个 schema 一一对应。

13. **`Do_Th_Send` 里的 `TCompute.RunC` 是否可能丢日志**
    - 源码用异步投递。
    - **不确定**：高并发下是否有竞态。

14. **`LF_CheckApiEx(BEACON_APP, REGISTER_API)` 的 3 秒缓存问题**
    - `RegisterTools` 首先调用它检查信标。
    - **不确定**：如果信标刚启动，是否会误判为不可用。

15. **C++ 生成器的 `LF_CDECL` 宏**
    - 源码里出现在 `Callback_*` 定义中。
    - **不确定**：`LF_CDECL` 定义在哪里（LingoFuse.hpp 或 LingoFuse.h）。
    - **建议**：编译前确认 `LF_CDECL` 已定义。

16. **`GenerateAll` 中的文件清单是否与 `GenerateSourceButtonClick` 实际落盘的文件名一致**
    - MCP 返回的 `files` 字段由 `internal_call` 手工拼接。
    - **不确定**：是否与 `SaveCode` 的实际文件名逐字一致。
    - **推测**：一致（同一份命名规则）。

17. **`SetModelJson` 是否保留传入的 JSON 字节级一致**
    - 源码先 `ParseText` 校验，再原样写入 `model_json_edit`。
    - **不确定**：`ParseText` 是否会对原文做规范化。
    - **推测**：不改（写入的是原始字符串）。

---

## 结语

### 本知识库的定位

一份**自包含、可操作、有边界**的 `code_decl_to_json_abi` 参考。它不假装能替代源码，但能让你在 90% 的场景下正确使用，并在剩下 10% 的场景下知道该停下来问人。

### 核心承诺

- **自我审视**：每一条结论都经过源码逐行核对。
- **可操作**：所有模式都可复制粘贴使用。
- **诚实**：不确定的地方明示，不误导。

### 快速回忆

1. **`SetSourceCode(Source, "pascal" | "c")`** — 只接受这两种源语言。
2. **`GenerateAll()`** — 必调，一次生成 17 件套。
3. **`GetLast<Lang><Side><Artifact>()`** — 17 个纯读 reader。
4. **不支持的例程静默丢弃**。
5. **JS 处理 `int64` 有精度风险**。

### 与相关单元的衔接

- 生成器依赖 `Z.Pascal_Func_Model` 与 `Z.Pascal_Func_Tool`。
- 生成的产物依赖 `lingofuse_import` 与 `lf_http_bridge_client`。
- 桥 `bridge.py` 负责 HTTP/JSON 与 LingoFuse 的转换（本知识库不覆盖其内部）。

---

**文档版本**：v1.0
**最后更新**：2026-09-23
**文档定位**：本文件是 `code_decl_to_json_abi` 的唯一权威参考。若发现与源码不一致，以源码为准。
