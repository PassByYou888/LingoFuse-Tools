# Pascal 声明规范（Z.Pascal_Func_Tool 工具链兼容）

**版本**：8.0
**最后更新**：2026-09-20
**约束对象**：`Z.Pascal_Func_Tool` → `Z.Pascal_Func_Model` → `pas_mcp_generator_tool` 完整工具链
**文档定位**：本规范即**解析契约**。任何偏离都会导致声明被**静默跳过**或**信息被静默丢失**。请严格按本规范书写。

---

## 本版修正摘要

| 编号 | 修正内容 | 章节 |
|:----:|---------|------|
| V8-1 | **重大修正**：`ExtractParamDescriptions` 已从 v2.8 的「逐行独立处理」升级为 v3.0 的「缩进感知状态机」 | §5.2 |
| V8-2 | **重大修正**：参数说明**不再要求集中堆叠**——支持多行缩进累积 | §5.4 |
| V8-3 | **重大修正**：v7.0 §5.6.8 描述的「参数名同名污染」问题在 v3.0 已通过「行首约束」解决 | §5.6.8 |
| V8-4 | **重大修正**：§0 第 8 条铁律从「不得含同名标识符」改为「参数块结构规范」 | §0 |
| V8-5 | **新增**：块注释前缀处理（C→Pascal 转换路径） | §4.7 |
| V8-6 | **新增**：模拟人类阅读失误场景章节 | §11 |
| V8-7 | **修正**：§4.3 注释风格推荐补充 C→Pascal 转换产物的说明 | §4.3 |
| V8-8 | **修正**：§4.5 触发条件速查表增加 `{ * }` 前缀场景 | §4.5.3 |
| V8-9 | **修正**：§5.6 返回值注释章节的多处细节说明 | §5.6 |
| V8-10 | **修正**：所有 Mermaid 图的渲染问题（subgraph ID 英文、节点标签加引号） | 全文 |
| V8-11 | **修正**：§3.3 禁止类型列表补充 `Pointer` 和空参数的说明 | §3.3 |
| V8-12 | **修正**：§1.3 位置示例补充嵌套函数场景 | §1.3 |

---

## 0. 三十秒速览

```mermaid
flowchart LR
    A["Write declaration"] --> B{"1. In interface?"}
    B -- No --> X["SKIP"]
    B -- Yes --> C{"2. Top-level?"}
    C -- No --> X
    C -- Yes --> D{"3. Has var/out?"}
    D -- Yes --> X
    D -- No --> E{"4. Types in whitelist?"}
    E -- No --> X
    E -- Yes --> F{"5. Comment above?"}
    F -- No --> X
    F -- Yes --> G{"6. Curly brace with closing brace?"}
    G -- Yes --> X2["Comment LOST"]
    G -- No --> H{"7. Return type in signature?"}
    H -- No --> X3["Return info LOST"]
    H -- Yes --> I{"8. Param name at line start?"}
    I -- No --> X4["Description LOST for that param"]
    I -- Yes --> J["Fully extracted"]

    style X fill:#ffe1e1
    style X2 fill:#ffe1e1
    style X3 fill:#ffe1e1
    style X4 fill:#fff4e1
    style J fill:#e1ffe1
```

**八条铁律**：

1. **位置**：`interface` 段 + 顶层
2. **关键字**：`function` 或 `procedure`
3. **修饰符**：只允许 `const`、`in`、空白（禁 `var`、`out`）
4. **类型**：参数与返回类型必须命中白名单
5. **注释**：紧邻上方（允许空行）
6. **注释体**：`{ }` 风格时不得含 `}`；推荐改用 `(* ... *)`
7. **返回值**：必须通过签名 `: T` 声明；注释里的 `@return` 不会进 JSON
8. **参数块结构**：参数名必须位于**行首**（或紧跟 Doxygen 标记之后）；其后的**缩进行**自动作为该参数的描述延续

**违反 1–4 = 整条声明跳过；违反 5–6 = 注释丢失；违反 7 = 返回类型缺失，整条声明被跳过；违反 8 = 该参数的描述丢失。**

> **与 v7.0 的关键差异**：v7.0 的第 8 条铁律是「注释里不得出现与参数名同名的独立标识符」。该规则在 v3.0 工具链中**已不再必要**——v3.0 采用**行首约束**（参数名必须位于行首），自然语言句子中间出现的同名标识符**不会**被误认为参数声明。v8.0 将第 8 条改写为反映 v3.0 实际行为的「参数块结构规范」。

---

## 1. 声明位置规则

### 1.1 unit 的解剖图

```mermaid
flowchart TB
    subgraph UnitBody["unit MyUnit"]
        direction TB
        INTF["interface section<br/>ONLY here is extracted"]
        IMPL["implementation section<br/>ALL skipped"]
    end

    INTF --> T1["top-level function<br/>EXTRACT"]
    INTF --> T2["top-level procedure<br/>EXTRACT"]
    INTF --> T3["type / var / const<br/>NOT function declaration"]
    INTF --> T4["inside class<br/>SKIP"]
    INTF --> T5["inside record<br/>SKIP"]
    INTF --> T6["inside interface type<br/>SKIP"]
    IMPL --> I1["any declaration<br/>SKIP"]

    style INTF fill:#e1ffe1
    style IMPL fill:#ffe1e1
    style T1 fill:#e1ffe1
    style T2 fill:#e1ffe1
```

### 1.2 会提取 vs 不会提取

| 位置 | 结果 |
|------|------|
| `interface` 段顶层 | 提取 |
| `interface` 段的 `class` / `record` / `interface` 类型内部 | 跳过 |
| `implementation` 段任何位置 | 跳过 |
| 嵌套在其他函数内部 | 跳过 |
| 嵌套在 `type` 段的类型定义内部 | 跳过 |

### 1.3 位置示例

```pascal
unit MyUnit;

interface

// OK: top-level function
function Add(a, b: Integer): Integer;

// OK: top-level procedure
procedure Log(const msg: string);

// OK: nested in another function -> skipped
procedure Outer;
  // This inner procedure is skipped (nested inside Outer)
  procedure Inner;
  begin
  end;
begin
end;

type
  TMyClass = class
    // SKIP: class method
    function Multiply(x, y: Integer): Integer;
  end;

  TMyRecord = record
    // SKIP: record method
    procedure DoSomething;
  end;

  IMyInterface = interface
    // SKIP: interface method
    procedure DoIt;
  end;

implementation

// SKIP: not in interface section
function InternalHelper: Boolean;
begin
  Result := True;
end;

end.
```

---

## 2. 参数修饰符规则

### 2.1 修饰符判定图

```mermaid
flowchart TB
    A["Parameter modifier"] --> B{"Is var?"}
    B -- Yes --> X["SKIP whole declaration"]
    B -- No --> C{"Is out?"}
    C -- Yes --> X
    C -- No --> D{"Is const / in / blank?"}
    D -- Yes --> F["PASS"]

    style X fill:#ffe1e1
    style F fill:#e1ffe1
```

### 2.2 修饰符白名单

| 修饰符 | 是否允许 | 说明 |
|--------|:--------:|------|
| 空白（无修饰符） | 允许 | 默认值传递 |
| `const` | 允许 | 只读值传递 |
| `in` | 允许 | 只读值传递（Delphi 2009+，FPC 也支持） |
| `var` | 禁止 | **整条声明跳过** |
| `out` | 禁止 | **整条声明跳过** |

### 2.3 为什么禁止 `var` / `out`

`var` / `out` 是**引用传递**，无法映射到 JSON Schema 的**值类型**。工具链的设计前提是「参数可序列化」。

**正确做法**：改用 `const` + 返回值。

```pascal
// FORBIDDEN: reference passing
procedure Modify(var x: Integer);

// OK: value passing + return value
function Modify(const x: Integer): Integer;
```

### 2.4 修饰符组内广播

```pascal
// const applies to a, b, c (all three)
const a, b, c: Integer;

// const applies only to a
const a: Integer; b: Integer;
```

---

## 3. 类型白名单

### 3.1 类型分类

```mermaid
mindmap
  root(("Type whitelist"))
    IntegerFamily
      Integer
      Int64
      Cardinal
      Longint
      DWord
      Word
      SmallInt
      Byte
      UInt64
      LongWord
    FloatFamily
      Double
      Single
      Extended
      Real
    StringFamily
      string
      AnsiString
      UnicodeString
      PChar
      PAnsiChar
      PWideChar
      TP_String
      TPascalString
      TUPascalString
      U_String
```

### 3.2 类型归一化表

| 原始类型 | 归一化为（tnf_Json 模式） | 归一化为（tnf_ABI 模式） | JSON Schema 类型 |
|----------|:------------------------:|:------------------------:|:----------------:|
| 整数族全部 | `int64` | 原始类型小写（如 `integer`） | `integer` |
| 浮点族全部 | `double` | 原始类型小写（如 `double`） | `number` |
| 字符串族全部 | `string` | 原始类型小写（如 `string`） | `string` |

> **模式说明**：`TPascal_Func_Model.Typ_Normalize_Func` 决定使用哪种归一化。默认是 `tnf_Json`，用于生成 MCP tool 的 JSON schema；`tnf_ABI` 用于保留原始类型名，便于生成 ABI 层代码。

### 3.3 明确禁止的类型

**以下类型一律导致整条声明跳过**：

| 类别 | 类型 |
|------|------|
| 布尔 | `Boolean` |
| 变体 | `Variant` |
| 数组 | `array of X` / `array[0..N] of X` |
| 记录/结构体 | `TPoint` / `TRect` / 自定义 record |
| 日期时间 | `TDateTime` |
| 类 | `TObject` / `TStringList` / 自定义 class |
| 接口 | `IInterface` / 自定义 interface |
| 枚举 | `TColor` / 自定义 enum |
| 集合 | `set of X` |
| 泛型 | `TList<X>` / `TGenericList<X>` |
| 事件 | `TNotifyEvent` |
| **无类型指针** | **`Pointer` / `PInteger` / `PByte`** |
| 匿名方法 | `reference to procedure` |
| 无类型参数 | 无名参数（如 `array of` 中省略元素类型） |

> **补充说明（v8.0 新增）**：`Pointer` 虽然在 C 侧映射表中有对应（`void *`），但在**Pascal 侧**不被接受。原因是 `Pointer` 无法确定语义大小，无法安全序列化。若必须传递指针语义，请改用 `Int64` 承载地址值。

### 3.4 边界示例

```pascal
// PASS
function Add(a, b: Integer): Integer;
function Sqrt(x: Double): Double;
function Echo(const s: string): string;

// SKIP: Boolean return
function IsEven(x: Integer): Boolean;

// SKIP: array parameter
function Total(const arr: array of Integer): Integer;

// SKIP: generic method
function GetItem<T>(const list: TList<T>): Integer;

// SKIP: Pointer parameter (v8.0 补充说明)
function GetBuffer(const p: Pointer): Integer;
```

---

## 4. 注释绑定规则

### 4.1 绑定规则图

```mermaid
flowchart TB
    A["Above declaration"] --> B{"Blank line?"}
    B -- No --> C["Bind nearest comment"]
    B -- Yes --> D{"Comment above blank?"}
    D -- Yes --> E["Bind nearest comment"]
    D -- No --> F["Comment empty"]

    G["Below declaration (trailing)"] --> H["NOT bound"]

    style C fill:#e1ffe1
    style E fill:#e1ffe1
    style F fill:#fff4e1
    style H fill:#ffe1e1
```

### 4.2 绑定规则表

| 情形 | 是否绑定 |
|------|:--------:|
| 注释 → 声明（紧邻） | 绑定 |
| 注释 → 空行 → 声明 | 绑定 |
| 注释1 → 注释2 → 声明 | 全部绑定 |
| 注释1 → 空行 → 注释2 → 声明 | 绑定注释2 |
| 声明 → 尾随注释 | 不绑定 |

### 4.3 注释风格的推荐顺序

**推荐顺序（从高到低）**：

| 优先级 | 风格 | 原因 |
|:------:|------|------|
| **1** | `(* ... *)` | 结束符 `*)` 在自然语言和 JSON 中罕见，最安全 |
| **2** | `// ...` | 到行末结束，完全不受花括号影响 |
| **3** | `{ ... }` | **仅当注释体内绝对不含 `}` 时使用** |

**规则**：

- **默认用 `(* ... *)`**。
- 若注释体是单行且不含 `}`，`//` 也可。
- `{ ... }` 只用于最简短的注释（如 `{ TODO: ... }`）。

**C→Pascal 转换产物的说明（v8.0 新增）**：

当输入是 C 头文件时，`Translate_C_Typ_To_Pascal` 会把 C 注释转换为 Pascal 风格的 `{ ... }`，其中**从第二行起每行携带 ` * ` 前缀**：

```
{ first line
 * second line
 * third line }
```

这种由**工具链自动生成**的 `{ ... }` 形式**无法避免**，但 **v3.0 的 `Z.Pascal_Func_Model` 会自动剥离 ` * ` 前缀**，因此不影响参数描述提取。**人工书写 Pascal 声明时**，仍然推荐使用 `(* ... *)`。

### 4.4 尾随注释不绑定（易错点）

```pascal
// WRONG: trailing comment is ignored
function Foo: Integer; // this is a trailing comment

// OK: preceding comment is bound
// this is a preceding comment
function Bar: Integer;
```

### 4.5 致命坑：`{ }` 注释体内出现 `}` 会导致注释整段丢失

**触发条件**：`{ ... }` 风格的注释体内**出现任何 `}` 字符**。
**后果**：该声明的 `Comment` 字段变为空字符串（JSON 序列化后 `"Comment": ""`）。

#### 4.5.1 根因机制

```mermaid
flowchart TD
    A["Source comment with JSON snippet<br/>{ parse format with ok true }"] --> B["TTextParsing tsPascal"]
    B --> C["Pascal curly brace comment<br/>not nested, ends at first closing brace"]
    C --> D["Comment token cut short:<br/>Token1 = ttComment<br/>Token2 = ttSymbol closing<br/>Token3 = function"]
    D --> E["ExtractPrecedingComments<br/>scan backward from function"]
    E --> F["Hit isolated closing brace, break"]
    F --> G["Result empty<br/>Comment field blank"]

    style C fill:#ffe1e1,stroke:#a00,stroke-width:2px
    style G fill:#ffe1e1,stroke:#a00,stroke-width:2px
```

#### 4.5.2 诊断口诀

> **Comment 为空 = 结构问题，先查 `}`；Comment 乱码 = 编码问题，查代码页。**

#### 4.5.3 触发条件速查（v8.0 补充）

| 注释体内的情况 | 是否触发 |
|----------------|:--------:|
| 无 `}` | 不触发 |
| 单个 `}` | **触发** |
| 全角 `｝`（U+FF5D） | 不触发 |
| `(* ... *)` 内的 `}` | 不触发 |
| `(* ... *)` 内的 `*)` | **触发** |
| `// ... }` | 不触发 |
| **C→Pascal 转换产物 `{ * ... }` 内的 `}`** | **触发**（转换前 C 侧的 `}` 会导致此问题） |

#### 4.5.4 修复方案

**首选**：改用 `(* ... *)`。

```pascal
(*
  Returns the configuration JSON.
  Example: a JSON object with host and port fields.
*)
function GetConfig: string;
```

**次选**：改用 `//`。

```pascal
// Returns the configuration JSON.
// Example: a JSON object with host and port fields.
function GetConfig: string;
```

---

### 4.6 tool description 的拼接规则

**`pas_mcp_generator_tool` 使用 `GetFullDescription(Comment)` 生成 tool description。它的行为如下**：

| 步骤 | 行为 |
|------|------|
| 1 | 按 `#10` / `#13` 把 `Comment` 拆分为行 |
| 2 | 跳过**空行** |
| 3 | 跳过**以 `@` 开头的行**（Doxygen 标签行） |
| 4 | 去掉行首的 `*` 和 `**`（块注释的延续标记） |
| 5 | 剩下的行**用空格连接为一行** |
| 6 | 最多保留 200 字符 |

**含义**：

- **多行注释被压成一行**——tool description 是单行字符串。
- **`@param` / `@return` 等 Doxygen 标签行会被跳过**——它们不进 description。
- **`{ }` / `(* *)` / `//` 的注释符号已被剥掉**——不会出现在 description 里。

**示例**：

```pascal
(*
  Computes the sum of two integers.
  source: first addend
  lang:   second addend

  @return the sum

  Return value: this function returns an Integer.
*)
function Add(source, lang: Integer): Integer;
```

生成的 tool description = `Computes the sum of two integers. source: first addend lang:   second addend Return value: this function returns an Integer.`

（`@return the sum` 整行被跳过。）

**因此**：

- **tool description 里会出现参数名描述**——这会让描述变长。
- **tool description 里不会出现 `@param` / `@return` 行**——它们被跳过。
- **若注释整体过长，description 会被截断到 200 字符**。

**最佳实践**：

- 注释的**第一行**写函数用途的一句话简述。
- **参数说明放在注释中段**，每行一个参数。
- **返回值说明放在注释末段**，以 `返回值说明：` 开头。
- **避免在注释里写无关的长段落**。

---

### 4.7 块注释前缀处理（v8.0 新增）

**背景**：当输入是 C 头文件时，经过 `Fill_C` + `Translate_C_Typ_To_Pascal` 转换后，元数据中的 `Comment` 字段形如：

```
{ @param source source text
 * @param lang   language name }
```

**从第二行起，每行携带 ` * ` 前缀**。这个前缀是 C 风格块注释的延续标记。

**v3.0 的 `Z.Pascal_Func_Model` 会自动剥离这个前缀**：

| 原始行 | 剥离后（用于解析） |
|--------|--------------------|
| `' @param source source text'` | `' @param source source text'`（无 `*`，不动） |
| `' * @param lang language name'` | `' @param lang language name'`（剥 `*`） |
| `' *         continuation'` | `'         continuation'`（剥 `*`，保留缩进） |

**关键契约**：

- 剥离**只在行首空白之后**遇 `*` 时触发。
- 剥离后**保留剩余所有字符**（包括内容自身的缩进）。
- 缩进层级基于剥离后的内容行计算。

**对用户的影响**：

- **人工书写 Pascal 声明**：`Comment` 字段不带 ` * ` 前缀，按本规范书写即可。
- **输入 C 头文件**：`Comment` 字段带 ` * ` 前缀，v3.0 自动剥离，无需用户处理。

---

## 5. 参数描述与返回值注释

### 5.1 数据流总览

```mermaid
flowchart LR
    SRC["Source code"] --> PARSER["TTextParsing"]
    PARSER --> COMMENTS["ttComment tokens<br/>adjacent to declaration"]
    PARSER --> SIGNATURE["Function signature"]

    COMMENTS --> EXTRACT["ExtractParamDescriptions"]
    COMMENTS --> FULLDESC["GetFullDescription"]
    SIGNATURE --> RT["ReturnType from : T"]
    SIGNATURE --> PARAMS["Parameter name list"]

    EXTRACT --> PDESC["Params Description field"]
    FULLDESC --> TDESC["tool description"]
    RT --> RT_JSON["ReturnType field"]
    PARAMS --> PARAMS_JSON["Params field"]

    style EXTRACT fill:#e8f4ff,stroke:#444
    style FULLDESC fill:#fff7e6,stroke:#444
    style RT fill:#e8ffe8,stroke:#0a0
    style PDESC fill:#e8ffe8,stroke:#0a0
    style TDESC fill:#ffe6e6,stroke:#a00
```

### 5.2 参数描述提取规则（v8.0 重大修正）

> **v7.0 的描述已过时**。v7.0 描述的「逐行独立处理」是 v2.8 的行为；v3.0 已升级为**缩进感知状态机**。

`ExtractParamDescriptions` 的实际行为（v3.0）：

| 步骤 | 行为 |
|------|------|
| 1 | 调用 `CleanComment` 剥离注释标记并统一 LF 行分隔符 |
| 2 | 按 `#10` 把 `Comment` 拆分为行 |
| 3 | 对每行调用 `GetContentLine` 剥离块注释 `*` 前缀（C→Pascal 路径） |
| 4 | 维护状态：`CurrentParam` / `CurrentDesc` / `ParamIndent` |
| 5 | **空白行** → 终止当前块 |
| 6 | **识别为参数声明**（行首参数名或 Doxygen 形式） → 终止当前块，开始新块 |
| 7 | **缩进 > ParamIndent** → 追加到当前描述（含原始缩进） |
| 8 | **其他** → 终止当前块 |

**参数声明识别规则**：

参数名必须是**行首第一个标识符**（或 Doxygen 标记之后的第一个标识符）：

| 形式 | 语法 | 例 |
|:----:|------|-----|
| A | `name ...` | `source: 源码文本` |
| B | `@name ...` / `\name ...` | `@source 源码文本` |
| C | `@param name ...` / `\arg name ...` / `@parameter name ...` | `@param source 源码文本` |

**关键约束**：参数名必须位于**行首**（或 Doxygen 标记后）。出现在自然语言句子中间的同名标识符**不会**被误识别为参数声明。

**多行描述累积**：

识别为参数声明后，**后续缩进更深的行**会自动追加到该参数的描述中。

**示例**：

```pascal
(*
  target: target language, pick one:
            pascal_service   generate Pascal service
            pascal_call      generate Pascal call
            python_service   generate Python service
          <unit> is the normalized UnitName.
*)
function Generate(target: string): string;
```

提取结果：

- `target` 的描述 = `"target language, pick one:\n            pascal_service   generate Pascal service\n            pascal_call      generate Pascal call\n            python_service   generate Python service\n          <unit> is the normalized UnitName."`

（缩进和换行全部保留。）

**分隔符剥离规则**：

参数名之后的分隔符会被循环剥离，支持 ASCII 和全角：

| 字符 | Unicode |
|:----:|:-------:|
| `:` | U+003A |
| `=` | U+003D |
| `：` | U+FF1A |
| `＝` | U+FF1D |

### 5.3 参数描述格式

**格式 A：冒号分隔**

```pascal
(*
  Computes the sum of two integers.
  source: first addend
  lang:   second addend
*)
function Add(source, lang: Integer): Integer;
```

**格式 B：等号分隔**

```pascal
(*
  source = first addend
  lang   = second addend
*)
function Add(source, lang: Integer): Integer;
```

**格式 C：Doxygen**

```pascal
(*
  @param source first addend
  @param lang   second addend
*)
function Add(source, lang: Integer): Integer;
```

**格式 D：空格分隔**

```pascal
(*
  source  first addend
  lang    second addend
*)
function Add(source, lang: Integer): Integer;
```

**格式 E：多行缩进延续（v8.0 新增）**

```pascal
(*
  target: target language, pick one:
            pascal_service   generate Pascal service
            pascal_call      generate Pascal call
          <unit> is the normalized UnitName.
*)
function Generate(target: string): string;
```

### 5.4 参数描述的堆叠规则（v8.0 修正）

> **v7.0 的「参数说明必须集中在一起，中间不能夹杂与参数无关的内容」已不再必要**。

**v3.0 的实际行为**：

- **每个参数声明块独立处理**：识别一个参数名后，**后续缩进更深的行**被吸收到该参数描述。
- **不要求所有参数说明集中在一起**：不同参数的说明块**可以分散**在注释的不同位置。
- **块内不夹杂无关内容**：一个参数块的延续行必须是该参数的说明，不能夹杂其他内容的歧义。

**推荐写法**：

1. **函数用途**（1–2 行）放**最前**。
2. **参数说明块**放**中段**，每行一个参数。
3. **返回值说明块**放**末段**，以 `返回值说明：` 开头。
4. **多行参数说明**：用缩进延续（后续行缩进更深）。

**正确示例**：

```pascal
(*
  Computes the product of two integers.

  source: first multiplicand
  lang:   second multiplicand

  Returns: this function returns an Integer.
*)
function Mul(source, lang: Integer): Integer;
```

**多行参数示例**：

```pascal
(*
  Generates code for the given target.

  model_json: the model JSON produced by abi_decl_to_json.
  target: target language, pick one:
            pascal_service   generate Pascal service unit
            pascal_call      generate Pascal call unit
            python_service   generate Python service module
          <unit> is the normalized UnitName.

  Returns: this function returns a string.
*)
function abi_generate_to_text(model_json: string; target: string): string;
```

**分散写法（也可接受）**：

```pascal
(*
  Function purpose.

  source: source text.

  Some free-form description in between.

  lang: language name.

  Returns: ...
*)
```

（`source` 和 `lang` 的描述分别在其块内独立提取，中间的自由描述被忽略。）

### 5.5 参数名匹配规则

| 规则 | 说明 |
|------|------|
| 大小写 | **不敏感**（`Source` 匹配 `source`） |
| 位置 | 参数名必须位于**行首**（或 Doxygen 标记之后） |
| 多行 | 缩进更深的后续行自动累积 |
| 每块一个参数 | 一个参数声明块只对应一个参数 |

---

### 5.6 返回值的注释写法（保留 v7.0 核心内容）

> **本节解决一个长期误解：很多人以为注释里的 `@return` 会被提取到 JSON。实际上不会。**

#### 5.6.1 数据流：什么进 JSON，什么不进 JSON

```mermaid
flowchart TB
    SRC["Source snippet"] --> J["JSON output"]

    SRC --> F1["Function name"]
    SRC --> F2["function or procedure"]
    SRC --> F3["Parameter name list"]
    SRC --> F4["Parameter types"]
    SRC --> F5["Return type from : T"]
    SRC --> F6["Adjacent comment"]

    F1 --> J1["Name field OK"]
    F2 --> J2["IsFunction field OK"]
    F3 --> J3["Params Name field OK"]
    F4 --> J4["Params Typ and PascalType OK"]
    F5 --> J5["ReturnType field OK"]
    F6 --> J6["Comment field OK (plain text)"]

    F6 --> F6a["Param name in comment"]
    F6a --> J7["Params Description field OK"]

    F6 --> F6b["@return or backslash-return"]
    F6b --> J8["NOT in JSON"]

    F6 --> F6c["Return value description line"]
    F6c --> J9["NOT in JSON, only in Comment"]

    style J5 fill:#e8ffe8,stroke:#0a0,stroke-width:3px
    style J7 fill:#e8ffe8,stroke:#0a0,stroke-width:3px
    style J8 fill:#ffe6e6,stroke:#a00,stroke-width:3px
    style J9 fill:#ffe6e6,stroke:#a00,stroke-width:3px
```

**表格式总结**：

| JSON 字段 | 来源 | 是否包含返回值信息 |
|-----------|------|:------------------:|
| `Name` | 函数名 | 否 |
| `IsFunction` | `function` / `procedure` | 否 |
| `Params[i].Name` | 参数列表 | 否 |
| `Params[i].Typ` | 参数类型（原始） | 否 |
| `Params[i].PascalType` | 参数类型（归一化） | 否 |
| `Params[i].Description` | 注释中 `参数名: 描述` | 否 |
| **`ReturnType`** | **签名里的 `: T`** | **是（唯一来源）** |
| `Comment` | 注释全文（纯文本） | 若含文字描述，只在此 |

**结论**：

1. **`ReturnType` 是唯一结构化的返回值信息**——它来自**函数签名的类型部分**。
2. **注释里的任何返回值描述都不会进结构化字段**——它们只能留在 `Comment` 纯文本里。
3. **LLM 要理解返回值语义，必须同时看**：`ReturnType`（结构化）+ `Comment`（纯文本）。

#### 5.6.2 `ReturnType` 的归一化

`ReturnType` 字段在 `TPascal_Func_Model` 里会被**归一化**，具体取决于 `Typ_Normalize_Func`：

| 签名里的类型 | `tnf_Json` 模式 | `tnf_ABI` 模式 |
|--------------|:---------------:|:--------------:|
| 任意整数族 | `int64` | 原始类型小写（如 `integer`） |
| 任意浮点族 | `double` | 原始类型小写（如 `double`） |
| 任意字符串族 | `string` | 原始类型小写（如 `string`） |

**含义**：

- **JSON 里看不到原始类型**——`ReturnType` 是 `int64` 而不是 `Integer`。
- **若需原始类型，看 `Comment` 或 `Params[i].Typ`**——但注释不是结构化的。
- **工具链的设计前提**：调用方不需要区分 `Integer` / `Int64`，都用 64 位整数传。

#### 5.6.3 为什么工具链不提取返回值描述

设计取舍：

| 方案 | 优点 | 缺点 |
|------|------|------|
| 新增 `ReturnDescription` 字段 | 信息完整 | 需改 `TFunctionStructure` / `LoadFromParser` / `SaveToJson`，影响面大 |
| 不提取（现状） | 简单，不动既有代码 | 返回值描述只能靠 LLM 从 `Comment` 里读 |
| 把返回值描述塞进 `Comment` | 简单 | LLM 需要从纯文本里提取 |

**当前选择第三种**：返回值描述**留在 `Comment` 里**，LLM 从纯文本里读取。**这也是为什么注释要写清楚**——它是 LLM 理解返回值语义的**唯一补充来源**。

#### 5.6.4 正确的返回值注释写法

**必须通过函数签名的 `: T` 声明返回类型**。注释里的返回值描述是**可选补充**。

**推荐写法**：

```pascal
(*
  Computes the sum of two integers.

  source: first addend
  lang:   second addend

  Return value: this function returns an Integer representing the sum.
*)
function Add(source, lang: Integer): Integer;
```

**要点**：

| 元素 | 作用 |
|------|------|
| `: Integer` | **唯一**被提取的返回值信息 → 归一化为 `int64` |
| `返回值说明：本函数返回 Integer 类型，...` | 给**人类 / LLM** 看的补充说明，**不进结构化字段** |
| `Integer` 出现在说明里 | **不会**被误认为参数名（因为它是类型名，且在句子中间） |

#### 5.6.5 v6.0 错误说法修正

**v6.0 曾说**：`返回值说明：` 可能被误认为参数。

**v7.0 及 v8.0 修正**：**不会**。

**原因**：`ExtractParamDescriptions` 要求参数名必须位于**行首**。`返回值说明` 位于行首，但它不是参数名，所以被跳过。`Integer` 出现在句子中间，也不满足行首约束。

**实测结论**：`返回值说明：...` 是**安全**的。

#### 5.6.6 反面示例

**错误：依赖注释里的返回值描述**

```pascal
(*
  @return the sum
*)
function Add(source, lang: Integer): Integer;
```

生成器提取的 `ReturnType` 是 `'int64'`，`@return the sum` **不会**进任何结构化字段。

**错误：`procedure` 里写 `@return`**

```pascal
(*
  @return nothing
*)
procedure Log(const msg: string);
```

`procedure` **没有 `ReturnType` 字段**。`@return` 被完全忽略。

**错误：返回类型不在白名单**

```pascal
(*
  Return value: a boolean.
*)
function IsEven(x: Integer): Boolean;
```

`Boolean` **不在白名单**，整条声明被**跳过**。

#### 5.6.7 推荐模板

```pascal
(*
  <function purpose in one or two lines>.

  <param1>: <description of param1>
  <param2>: <description of param2>

  Return value: this function returns <type>, <semantic description>.
*)
function <name>(<param1>: <type1>; <param2>: <type2>): <return type>;
```

**规则**：

- 参数说明块**集中在注释中段**。
- 返回值说明块**独立**放在注释末段，以 `返回值说明：` 开头。
- 返回值说明里**不要再出现 `<参数名>:` 格式**——避免阅读者困惑。

#### 5.6.8 注释里出现参数名同名标识符的风险（v8.0 重大修正）

> **v7.0 描述的问题在 v3.0 中已解决。**

**v7.0 描述的问题**：注释的任何一行出现与参数名同名的独立 `ttAscii` token，该行的其余内容可能被误认为该参数的描述。

**v3.0 的解决方案**：**行首约束**。参数名必须位于**行首**（或 Doxygen 标记后）才被识别为参数声明。

**示例（v3.0 中已安全）**：

```pascal
(*
  Reads configuration.
  host: host name
  port: port number

  JSON format is a key-value object with host and port fields.
  Note that host is the host name and port is the port number.
*)
function GetConfig(host: string; port: Integer): string;
```

分析：

- `host: host name` → 行首 `host` → 正常提取。
- `port: port number` → 行首 `port` → 正常提取。
- `JSON format is ...` → 行首 `JSON` 非参数名 → 跳过。
- `Note that host is the host name and port is the port number.` → 行首 `Note` 非参数名 → **整行跳过**，`host` 和 `port` 虽在句中但**不会被误识别**。

**结果**：`host="host name"`、`port="port number"`。**无污染**。

**仍存在的边缘情况**：

如果某行以参数名**开头**但不是参数声明行，仍可能被误识别。例如：

```pascal
(*
  host: host name

  host can also be an IP address.
*)
function Connect(host: string);
```

分析：

- `host: host name` → 正常提取 `host="host name"`。
- `host can also be an IP address.` → **行首 `host` 匹配** → Rule 3（空格分隔）命中 → 描述变成 `"host name host can also be an IP address."`（**被污染**）。

**规避方案**：

1. **改写句式**：把这类说明合并到参数描述行：
   ```pascal
   (*
     host: host name (can also be an IP address)
   *)
   ```

2. **用引号包裹**：把行首的参数名用引号或反引号包裹：
   ```pascal
   (*
     host: host name

     `host` can also be an IP address.
   *)
   ```

3. **用中文描述代替**：
   ```pascal
   (*
     host: host name

     主机名也可以是 IP 地址。
   *)
   ```

4. **调整缩进**：让该行成为上一个参数块的延续（缩进更深）：
   ```pascal
   (*
     host: host name
           can also be an IP address.
   *)
   ```

#### 5.6.9 与 Doxygen `@return` 的关系

| 写法 | 提取结果 |
|------|----------|
| `@return the sum` | 不进任何结构化字段（`@` 使得该行被跳过） |
| `\return the sum` | 同上 |
| `返回值说明：两数之和` | 不进结构化字段，**但留在 `Comment` 里** |

**结论**：

- **`@return` / `\return` 是安全的**（不会被误认为参数），但也不会被提取。
- **`返回值说明：` 是推荐写法**——它留在 `Comment` 里，LLM 可以读到。
- **不要用 `返回值: xxx`**——虽然同样安全，但格式与参数描述接近，可能造成阅读者困惑。

---

## 6. 完整示例

### 6.1 正面示例（全部通过）

```pascal
unit SampleUnit;

interface

(*
  Computes the sum of two integers.

  source: first addend
  lang:   second addend

  Return value: this function returns an Integer representing the sum.
*)
function Add(source, lang: Integer): Integer;

(*
  Computes the product of two integers.

  @param source first multiplicand
  @param lang   second multiplicand

  Return value: this function returns an Integer representing the product.
*)
function Mul(source, lang: Integer): Integer;

(*
  String echo.

  s: string to echo

  Return value: this function returns a string identical to the input.
*)
function Echo(const s: string): string;

(*
  Logs a message. No return value.

  msg: log content
*)
procedure Log(const msg: string);

(*
  Returns the configuration JSON.

  Return value: this function returns a string containing JSON text.
*)
function GetConfig: string;

implementation

end.
```

### 6.2 多行参数描述示例（v8.0 新增）

```pascal
unit MultiLineDemo;

interface

(*
  Generates code for the given target.

  model_json: the model JSON produced by abi_decl_to_json.
  target: target language, pick one:
            pascal_service   generate Pascal service unit
            pascal_call      generate Pascal call unit
            python_service   generate Python service module
            python_call      generate Python call module
          <unit> is the normalized UnitName.

  Return value: this function returns a string containing the generated code.
*)
function abi_generate_to_text(model_json: string; target: string): string;

implementation

end.
```

**提取结果**：

| 参数 | 描述 |
|------|------|
| `model_json` | `the model JSON produced by abi_decl_to_json.` |
| `target` | `target language, pick one:\n            pascal_service   generate Pascal service unit\n            pascal_call      generate Pascal call unit\n            python_service   generate Python service module\n            python_call      generate Python call module\n          <unit> is the normalized UnitName.` |

### 6.3 反面示例（跳过或丢失）

```pascal
unit BadUnit;

interface

// SKIP: parameter has var
procedure Modify(var x: Integer);

// SKIP: returns Boolean
function IsEven(x: Integer): Boolean;

// SKIP: parameter has array
function Sum(const arr: array of Integer): Integer;

// SKIP: generic method
function GetItem<T>(const list: TList<T>): Integer;

// SKIP: pointer parameter (v8.0 note)
function GetBuffer(const p: Pointer): Integer;

// COMMENT LOST: curly brace comment contains closing brace
{
  Returns the configuration JSON.
  Example: a JSON object with host and port fields, closed by a brace.
}
function GetConfig: string;

// PARAM DESCRIPTION POLLUTED: line starts with parameter name
(*
  host: host name

  host can also be an IP address.
*)
function Connect(host: string): Boolean;

implementation

end.
```

---

## 7. 常见错误对照表

| 错误写法 | 后果 | 正确写法 |
|----------|------|----------|
| `procedure P(var x: Integer)` | 整条跳过 | `function P(const x: Integer): Integer` |
| `procedure P(out x: Integer)` | 整条跳过 | `function P: Integer` |
| `function F: Boolean` | 整条跳过 | `function F: Integer`（用 0/1 表示） |
| `function F(a: TPoint)` | 整条跳过 | 拆成 `Double` / `Integer` 参数 |
| `function F(a: array of Integer)` | 整条跳过 | 用 JSON 字符串或多次调用 |
| `function F(a: Pointer)` | 整条跳过 | 用 `Int64` 承载地址值 |
| 类方法 `TClass.F` | 跳过 | 移到顶层 |
| `implementation` 段函数 | 跳过 | 移到 `interface` 段 |
| 尾随注释 `function F; // comment` | 注释被忽略 | 改为前置注释 |
| `{ ... }` 内含 `}` | Comment 整段为空 | 改用 `(* ... *)` |
| `(* ... *)` 内含 `*)` | Comment 从 `*)` 处切断 | `*` 与 `)` 间加空格 |
| 依赖 `@return` 描述作为返回值信息 | 不进 JSON | 必须在签名里声明返回类型 |
| `procedure` 里写 `@return` | 被完全忽略 | `procedure` 不写返回值描述 |
| 返回值描述用 `返回值: xxx` 格式 | 阅读者困惑 | 用 `返回值说明：` |
| **参数名出现在句子中间** | **不会污染**（v3.0 行首约束） | 无需修正 |
| **参数名作为某行行首但不是声明** | **可能污染该参数** | 改写句式或调整缩进 |
| **参数说明分散在多处** | **v3.0 可正确处理**（每块独立） | 无需修正 |
| **多行参数说明** | **v3.0 自动累积**（缩进延续） | 无需修正 |

---

## 8. 自检清单（写完声明后逐项核对）

```mermaid
flowchart TB
    A["Wrote a declaration"] --> B{"1. In interface?"}
    B -- No --> X["Move to interface"]
    B -- Yes --> C{"2. Top-level?"}
    C -- No --> X2["Move to top-level"]
    C -- Yes --> D{"3. Has var/out?"}
    D -- Yes --> X3["Use const + return value"]
    D -- No --> E{"4. Types in whitelist?"}
    E -- No --> X4["Use integer / float / string"]
    E -- Yes --> F{"5. Comment above?"}
    F -- No --> X5["Move comment above"]
    F -- Yes --> G{"6. Curly brace with closing brace?"}
    G -- Yes --> X6["Switch to (* ... *)"]
    G -- No --> H{"7. Return type in signature?"}
    H -- No --> X7["Use : T in signature"]
    H -- Yes --> I{"8. Param name at line start?"}
    I -- No --> X8["Move param name to line start"]
    I -- Yes --> J["PASS"]

    style J fill:#e1ffe1
    style X fill:#ffe1e1
    style X2 fill:#ffe1e1
    style X3 fill:#ffe1e1
    style X4 fill:#ffe1e1
    style X5 fill:#ffe1e1
    style X6 fill:#ffe1e1
    style X7 fill:#ffe1e1
    style X8 fill:#ffe1e1
```

**八项检查**：

| 序号 | 检查项 | 不通过的动作 |
|:----:|--------|--------------|
| 1 | 在 `interface` 段？ | 移到 `interface` 段 |
| 2 | 在顶层？ | 移到顶层 |
| 3 | 参数不含 `var` / `out`？ | 改用 `const` + 返回值 |
| 4 | 所有类型在白名单？ | 改用整数 / 浮点 / 字符串 |
| 5 | 注释紧邻上方？ | 移动注释 |
| 6 | 注释体内不含 `}`？ | 改用 `(* ... *)` |
| 7 | 返回类型在签名里声明？ | 用 `: T` 声明，不要依赖注释 |
| 8 | 参数名在行首（或 Doxygen 标记后）？ | 移动参数名到行首 |

---

## 9. 最小可解析模板

```
unit <UnitName>;

interface

(*
  <function purpose in one or two lines>.

  <param1>: <description of param1>
  <param2>: <description of param2>

  Return value: this function returns <type>, <semantic description>.
*)
function <name>(<param1>: <type1>; <param2>: <type2>): <return type>;

implementation

function <name>(<param1>: <type1>; <param2>: <type2>): <return type>;
begin
  // implementation
end;

end.
```

**填空规则**：

| 占位符 | 可选值 |
|--------|--------|
| `<UnitName>` | 合法 Pascal 标识符 |
| `<name>` | 合法 Pascal 标识符 |
| `<paramN>` | 合法 Pascal 标识符 |
| `<typeN>` | 见 §3 白名单 |
| `<return type>` | 见 §3 白名单 |

**注意**：

- 模板固定使用 `(* ... *)` 注释，即使注释体内出现 `}` 也安全。
- 返回类型必须写在签名里（`function F: T`），注释里的返回值说明只是给人 / LLM 看的。
- 参数名必须位于**行首**，后续缩进行自动作为参数描述延续。

---

## 10. 设计原则

### 10.1 工具链的硬性假设

```mermaid
mindmap
  root(("Toolchain assumptions"))
    TopLevelOnly
      Skip class methods
      Skip nested functions
      Skip implementation section
    ValueTypesOnly
      Skip var and out
      Skip arrays records classes
      Skip generics and enums
      Skip pointers
    StructuredComments
      Adjacent to declaration
      Non-nested braces
      No closing brace inside
    StructuredParams
      Names from signature
      Descriptions from comment
      Names at line start
      Indented continuation
    StructuredReturn
      Type in signature
      Description in comment
      Description not in JSON
    SilentSkip
      No exception
      Record in Report
      Continue main flow
```

### 10.2 使用者的六条铁律

1. **写声明前先查白名单**——参数、返回类型必须在 §3 列表中。
2. **写完声明的自检**——是否在 `interface` 段？是否在顶层？是否含 `var` / `out`？
3. **注释体内有 `}` 时改用 `(* ... *)`**——见 §4.5。
4. **返回类型必须写在签名里**——`function F: T`，不要依赖注释——见 §5.6。
5. **参数名必须位于行首**——见 §5.2。
6. **多行参数说明用缩进延续**——见 §5.4。

### 10.3 本规范与旧版的关键差异

| 项目 | v4.0 | v5.0 | v6.0 | v7.0 | **v8.0** |
|------|:----:|:----:|:----:|:----:|:--------:|
| 注释空行允许 | 是 | 是 | 是 | 是 | 是 |
| 类型白名单 | 是 | 是 | 是 | 是 | 是 |
| `{ }` 内含 `}` 坑 | 否 | 是 | 是 | 是 | 是 |
| 返回值注释写法 | 否 | 否 | 是 | 是 | 是 |
| 数据流表 | 否 | 否 | 否 | 是 | 是 |
| `ReturnType` 归一化 | 否 | 否 | 否 | 是 | 是 |
| 参数堆叠规则 | 否 | 否 | 是 | 是 | 是 |
| tool description 拼接规则 | 否 | 否 | 否 | 是 | 是 |
| 注释风格推荐顺序 | 否 | 否 | 否 | 是 | 是 |
| 参数名同名标识符风险 | 否 | 否 | 否 | 是 | **是** |
| **参数描述状态机** | 否 | 否 | 否 | 否 | **是** |
| **多行参数描述累积** | 否 | 否 | 否 | 否 | **是** |
| **行首约束** | 否 | 否 | 否 | 否 | **是** |
| **块注释前缀处理** | 否 | 否 | 否 | 否 | **是** |
| **模拟阅读失误场景** | 否 | 否 | 否 | 否 | **是** |
| 铁律数 | 3 | 4 | 5 | 6 | **8** |
| 自检清单 | 5 | 6 | 7 | 8 | **8** |

---

## 11. 模拟人类阅读失误场景（v8.0 新增）

本节列出**读者容易误读**的场景，逐一解释实际行为。

### 11.1 误读场景 A：以为参数说明必须集中

**误读**：看到 §5.4 的「参数说明块放在中段」，以为**所有参数说明必须连续写在一起**。

**实际**：v3.0 中，**每个参数声明块独立处理**。不同参数的说明块**可以分散**在注释的不同位置。

**示例（合法）**：

```pascal
(*
  Function purpose.

  source: source text.

  Some free-form description in between.

  lang: language name.
*)
```

**如果你这样写，会怎样**：`source` 和 `lang` 的描述都会被正确提取。中间的自由描述被忽略。

**建议**：虽然合法，但为了**可读性**和 **tool description 拼接**的稳定性，推荐把参数说明集中在中段。

### 11.2 误读场景 B：以为必须避免在正文中提及参数名

**误读**：看到 §5.6.8 的「注释里出现参数名同名标识符的风险」，以为**注释正文里不能提及参数名**。

**实际**：v3.0 采用**行首约束**。**行首不是参数名**的行，即使中间含有参数名，也**不会被误识别**。

**示例（安全）**：

```pascal
(*
  host: host name

  This config controls the host and port used by the service.
*)
```

**如果你这样写，会怎样**：`host` 的描述 = `"host name"`。第二行中出现的 `host` 和 `port` **不会污染**。

**仍存在的边缘情况**：如果某行**以参数名开头**但**不是**参数声明行，可能被误识别。见 §5.6.8 的详细说明。

### 11.3 误读场景 C：以为多行参数说明会被丢弃

**误读**：看到 §5.2 的「每行只取一个参数描述」（这是 v2.8 的行为），以为**多行参数说明会被截断**。

**实际**：v3.0 采用**缩进感知状态机**。参数名后的**缩进更深的行**会自动累积。

**示例（合法）**：

```pascal
(*
  target: target language, pick one:
            pascal_service
            pascal_call
          <unit> is the normalized UnitName.
*)
```

**如果你这样写，会怎样**：`target` 的描述会包含全部三行延续内容。

### 11.4 误读场景 D：以为 `{ ... }` 完全不能用

**误读**：看到 §4.3 的「推荐顺序」（`{ ... }` 排第三），以为 `{ ... }` **不能用**。

**实际**：`{ ... }` **可以用**，只要**注释体内不含 `}`**。同时，**C→Pascal 转换产物**的 `{ ... }` 形式（带 ` * ` 前缀）由工具链自动生成，**无法避免**，但 v3.0 会自动处理。

**如果你这样写，会怎样**：

- **手写 `{ 简短说明 }`**（不含 `}`）：完全正常。
- **手写 `{ { ... } }`**（含 `}`）：注释丢失。

### 11.5 误读场景 E：以为返回值描述会被提取

**误读**：看到 §5.6 的「返回值的注释写法」，以为 `@return` 或 `返回值说明：` 会被**提取到 JSON 的某个字段**。

**实际**：**只有签名里的 `: T` 进 JSON**。注释里的返回值描述**只留在 `Comment` 纯文本**里。

**如果你这样写，会怎样**：

- `function F: Integer;` 加注释 `@return the result` → JSON 里只有 `ReturnType="int64"`，注释里的描述**不进 JSON**。
- LLM 要从 `Comment` 里读返回值语义。

**建议**：仍然写返回值说明，因为 LLM 会读 `Comment`。

### 11.6 误读场景 F：以为可以省略返回类型

**误读**：看到「`ReturnType` 归一化为 `int64`」，以为**可以省略签名里的 `: T`**，让工具链从注释推断。

**实际**：**必须显式声明 `: T`**。若省略，`decl_to_pascal` / `decl_to_c` 无法判断这是 `function` 还是 `procedure`，整条声明**可能被跳过**。

**如果你这样写，会怎样**：

```pascal
(*
  @return the sum
*)
function Add(source, lang: Integer);
```

**实际结果**：`Z.Pascal_Func_Tool` 的 `Fill_Pascal` 会报错 `function "Add" missing ":" or return type`，声明被跳过。

### 11.7 误读场景 G：以为 `in` 修饰符会被跳过

**误读**：看到 §2.2 的「`var` / `out` 被禁止」，以为 `in` 也被禁止。

**实际**：`in` **被允许**（Delphi 2009+，FPC 也支持）。它和 `const` 语义相近。

**如果你这样写，会怎样**：

```pascal
function F(in x: Integer): Integer;
```

**实际结果**：正常提取，与 `const x: Integer` 等价处理。

### 11.8 误读场景 H：以为参数名大小写敏感

**误读**：以为 `source: xxx` 和 `Source: xxx` 会被视为不同参数。

**实际**：参数名匹配**大小写不敏感**。`Source` 匹配 `source`。

**如果你这样写，会怎样**：

```pascal
(*
  SOURCE: source text
*)
function F(Source: string);
```

**实际结果**：`Source` 参数的描述 = `"source text"`。

### 11.9 误读场景 I：以为注释必须紧邻声明

**误读**：看到 §4.2 的「注释 → 空行 → 声明 → 绑定」，以为**必须**紧邻。

**实际**：注释与声明之间**可以有空行**，也**可以有多个连续注释**。工具链会从声明向前扫描，收集**所有连续的注释**作为 `Comment`。

**如果你这样写，会怎样**：

```pascal
// comment part 1

// comment part 2

function F: Integer;
```

**实际结果**：`Comment` = `"comment part 1\ncomment part 2"`（两段注释全部保留）。

### 11.10 误读场景 J：以为 C→Pascal 转换会丢失参数描述

**误读**：看到 C 头文件里的 Doxygen `/** */`，以为转换成 Pascal 后参数描述会**全部丢失**。

**实际**：v3.0 会自动处理 ` * ` 前缀。C 头文件的 Doxygen 注释**能正确提取参数描述**。

**如果你这样写**：

```c
/**
 * @param a first addend
 * @param b second addend
 */
int add(int a, int b);
```

**实际结果**：`a="first addend"`, `b="second addend"`。**完全保留**。

---

## 12. 修订历史

- **v8.0（2026-09-20）**：
  - **§5.2 重大修正**：`ExtractParamDescriptions` 从「逐行独立处理」升级为「缩进感知状态机」。
  - **§5.4 重大修正**：参数说明**不再要求集中堆叠**——支持多行缩进累积。
  - **§5.6.8 重大修正**：v7.0 描述的「参数名同名污染」在 v3.0 中已通过「行首约束」解决。
  - **§0 第 8 条铁律重写**：从「不得含同名标识符」改为「参数块结构规范」。
  - **§4.3 补充**：C→Pascal 转换产物的 ` * ` 前缀说明。
  - **§4.5.3 补充**：`{ * }` 前缀场景。
  - **§4.7 新增**：块注释前缀处理（C→Pascal 路径）。
  - **§6.2 新增**：多行参数描述示例。
  - **§3.3 补充**：`Pointer` 被拒绝的原因说明。
  - **§1.3 补充**：嵌套函数场景。
  - **§7 更新**：常见错误对照表新增 v8.0 修正项。
  - **§11 新增**：模拟人类阅读失误场景（10 个误读案例）。
  - **Mermaid 修复**：subgraph ID 全部改为英文；节点标签加引号；全角标点替换为 ASCII 或英文。
  - **§10.3 更新**：本规范与旧版关键差异表。

- **v7.0（2026-09-20）**：
  - 新增 §5.6.1「数据流：什么进 JSON，什么不进 JSON」。
  - 新增 §5.6.2「`ReturnType` 的归一化」。
  - 新增 §5.6.8「注释里出现参数名同名标识符的风险」。
  - 修正 §5.6.5：v6.0 说「`返回值说明：` 可能被误认为参数」，实际**不会**。
  - 新增 §4.6「tool description 的拼接规则」。
  - 新增 §4.3「注释风格的推荐顺序」。
  - §0 七条铁律 → 八条。
  - §8 自检清单七项 → 八项。

- **v6.0（2026-09-20）**：新增 §5.6「返回值的注释写法」。
- **v5.0（2026-09-20）**：新增 §4.5「`{ }` 注释内含 `}` 坑」。
- **v4.0（2026-09-10）**：重写，修正空行规则，明确类型白名单。
- **v3.0（2026-09-02）**：实例驱动。
- **早期版本**：初版。

---

**本规范为解析契约。任何偏离本规范的声明将被工具链静默跳过，或注释被静默丢失，或返回值描述被静默忽略，或参数描述被静默丢失。**

**遇到「Comment 为空」，先查 `}`；遇到「参数描述不见」，先查参数名是否在行首；遇到「参数描述奇怪」，先查是否有以参数名开头的非声明行。**