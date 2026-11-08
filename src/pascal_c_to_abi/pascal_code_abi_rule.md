# Pascal 声明编写规则（ABI 工具链）

**定位**：这是一份**编写指南**，不是源码解读。按本文写，声明就能被正确提取并生成；不按本文写，声明会被**静默跳过**（无错误、无警告，只在报告里留一行原因）。
**契约**：本文档是**解析契约**。偏离契约会导致声明被静默跳过、注释被静默丢弃、参数描述被静默丢失。

---

## 0. 30 秒速览

### 0.1 能写什么

```pascal
// 位于 interface 段的顶层声明
function Add(a, b: Integer): Integer;
procedure Log(const msg: string);
function Echo(const s: string): string;

// v10 新增：TBytes 二进制负载
procedure SendBytes(const Channel: string; const Data: TBytes);
function MakeBytes(const n: Integer): TBytes;
function EchoBytes(const Data: TBytes): TBytes;
```

### 0.2 不能写什么

```pascal
// 都会被静默跳过
procedure Modify(var x: Integer);                  // var 修饰符
procedure Fill(out y: Integer);                    // out 修饰符
procedure ProcessBytesMutable(var Data: TBytes);   // var 修饰的 TBytes
function  IsEven(x: Integer): Boolean;             // Boolean 不在白名单
function  Sum(const a: array of Integer): Integer; // 非字节的动态数组
function  Get(p: Pointer): Integer;                // Pointer 最终被拒绝
function  Wrap<T>(x: T): Integer;                  // 泛型
function  Now2: TDateTime;                         // TDateTime
function  GetConfig: TConfig;                      // record / class / enum / set

type
  TFoo = class
    function Bar: Integer;                          // 嵌套在 class 内
  end;

implementation
function Helper: Integer;                           // 位于 implementation 段
```

### 0.3 内容流向

| 你写的内容 | 去向 |
|------------|------|
| 签名（参数名、类型、返回类型） | 结构化 JSON（`Name`、`Params[i].Name`、`Params[i].Typ`、`ReturnType`） |
| 紧邻的注释 | `Comment` 字段；第一段非空非 `@` 段落 → 工具描述（截断 200 字符） |
| 注释里的 `name: desc` 行 | `Params[i].Description` |
| 注释里的 `@param` / `@return` | 只保留在 `Comment` 里，**不进入**结构化 JSON |
| 注释里的 `Return value: ...` | 只保留在 `Comment` 里，**不进入**结构化 JSON |

**AI 实际能看到的只有两样东西**：`Comment`（工具描述 + 参数描述）、`ReturnType`。其它内容不进 JSON。

---

## 1. 位置

### 1.1 规则

必须是 **`interface` 段**中的**顶层**声明。

- `implementation` 段中的声明**不会被提取**。
- 嵌套在 `class`、`record`、`interface` 内的声明**不会被提取**（虽然会被解析，但最终被过滤掉）。
- 单元必须包含完整的 `unit` / `interface` / `implementation` / `end.` 结构；缺任何一项，整个单元视为解析失败。

### 1.2 哪些位置不被接受

| 位置 | 结果 | 修复 |
|------|------|------|
| `implementation` 段 | 跳过 | 移到 `interface` 段 |
| `class` 内部 | 跳过 | 移到顶层 |
| `record` 内部 | 跳过 | 移到顶层 |
| `interface`（类型）内部 | 跳过 | 移到顶层 |
| 嵌套函数/过程内 | 跳过 | 移到顶层 |
| 单元无 `interface` / `implementation` / `end.` | 整个单元失败 | 补全结构 |

### 1.3 示例

```pascal
unit MyUnit;

interface

// ✅ 被提取
function Add(a, b: Integer): Integer;
procedure Log(const msg: string);

type
  TFoo = class
    function Nested: Integer;     // ❌ 嵌套在 class 内
  end;

  TBar = record
    procedure Nested;             // ❌ 嵌套在 record 内
  end;

implementation

function Hidden: Integer;         // ❌ 位于 implementation 段
begin
  Result := 0;
end;

end.
```

---

## 2. 参数修饰符

### 2.1 规则

| 修饰符 | 是否允许？ |
|--------|:----------:|
| （无） | ✅ |
| `const` | ✅ |
| `in` | ✅ |
| `var` | ❌ 整条声明被跳过 |
| `out` | ❌ 整条声明被跳过 |

**对 `TBytes` 的补充**：`TBytes` 参数可以用 `const`（推荐），但**不能**用 `var` / `out`——引用传递无法序列化。

### 2.2 为什么 `var` / `out` 不行

ABI 层是跨进程/跨语言的，`var` / `out` 通过引用写回调用方。跨进程时"引用"没有意义——被调方修改的是自己进程里的副本，无法传回调用方。

### 2.3 修复方式

改为返回值，而不是通过引用写回。

```pascal
// 错误
procedure Increment(var x: Integer);
procedure AppendByte(var Data: TBytes; const b: Byte);

// 正确
function Increment(const x: Integer): Integer;
function AppendByte(const Data: TBytes; const b: Byte): TBytes;
```

### 2.4 多参数共享修饰符

```pascal
function GroupConst(const a, b, c: Integer): Integer;
// 等价于三个独立的 const 参数：a、b、c 都是 const + Integer
```

```pascal
procedure Swap(var a, b: Integer);
// 两个参数都是 var → 整条声明被跳过
```

---

## 3. 类型规则

### 3.1 允许的类型（三大类）

| 类别 | 类型 |
|------|------|
| 整型 | `Integer`、`Int64`、`Cardinal`、`LongInt`、`DWord`、`Word`、`SmallInt`、`Byte`、`UInt64`、`LongWord` |
| 浮点 | `Double`、`Single`、`Extended`、`Real` |
| 字符串 | `string`、`AnsiString`、`UnicodeString`、`PChar`、`PAnsiChar`、`PWideChar`、`TP_String`、`TPascalString`、`TUPascalString`、`U_String` |
| **二进制**（v10 新增） | **`TBytes`**、**`array of Byte`**（两者等价） |

### 3.2 跨语言映射表

你写的 Pascal 类型，在 JSON 描述、Pascal ABI 代码、C++ ABI 代码中的最终形态：

| 你写的类型 | JSON 描述 | 生成的 Pascal ABI | 生成的 C++ ABI |
|------------|:---------:|:-----------------:|:--------------:|
| `Integer` | `int64` | `Integer` | `std::int32_t` |
| `Int64` | `int64` | `Int64` | `std::int64_t` |
| `Cardinal` | `int64` | `Cardinal` | `std::uint32_t` |
| `LongInt` | `int64` | `LongInt` | `std::int32_t` |
| `DWord` | `int64` | `DWord` | `std::uint32_t` |
| `Word` | `int64` | `Word` | `std::uint16_t` |
| `SmallInt` | `int64` | `SmallInt` | `std::int16_t` |
| `Byte` | `int64` | `Byte` | `std::uint8_t` |
| `UInt64` | `int64` | `UInt64` | `std::uint64_t` |
| `LongWord` | `int64` | `LongWord` | `std::uint32_t` |
| `Single` | `double` | `Single` | `float` |
| `Double` | `double` | `Double` | `double` |
| `Extended` | `double` | `Extended` | `double`（精度损失） |
| `Real` | `double` | `Real` | `double`（精度损失） |
| 字符串族（全部） | `string` | `string` | `std::string` |
| **`TBytes` / `array of Byte`** | **`TBytes`** | **二进制负载**（工具链自动处理） | **`std::vector<std::uint8_t>`** |

### 3.3 禁止的类型及原因

以下任意一种都会导致**整条声明被跳过**。

| 类别 | 示例 | 为什么不行 | 替代 |
|------|------|------------|------|
| 布尔 | `Boolean`、`WordBool`、`LongBool` | 跨语言布尔表示不一致 | `Integer`（0/1）或 `Byte` |
| 变体 | `Variant`、`OleVariant` | 无法序列化 | 拆成具体类型 |
| 非字节动态数组 | `array of Integer`、`array of string` | 只支持字节序列 | 用 `TBytes` 序列化 |
| 静态数组 | `array[0..N] of X` | 无法序列化 | 用 `TBytes` |
| 记录 | `TPoint`、`TRect`、自定义 `record` | 跨语言结构不一致 | 拆成多个标量参数，或 `TBytes` |
| 类 | `TObject`、`TStringList` | 无法序列化 | 拆成多个标量参数 |
| 接口 | `IInterface` | 无法序列化 | 拆成多个标量参数 |
| 枚举 | `TColor` | 跨语言枚举表示不一致 | `Integer` |
| 集合 | `set of X` | 无法序列化 | `Integer` 位掩码 |
| 泛型 | `TList<X>`、`TGenericList<X>` | 无法序列化 | 拆成多个标量参数 |
| 日期/时间 | `TDateTime`、`TDate`、`TTime` | 跨语言时间表示不一致 | `Int64`（Unix 时间戳）或 `string`（ISO 8601） |
| 指针 | `Pointer`、`PInteger`、`PByte` | 地址无跨进程意义 | `Int64`（承载地址）或 `TBytes` |
| 事件 | `TNotifyEvent` | 无法序列化 | 拆成标量回调参数 |
| 匿名方法 | `reference to procedure` | 无法序列化 | 拆成标量回调参数 |

### 3.4 指针：为什么不行，如何替代

`Pointer` 在**最终生成阶段被拒绝**。虽然声明能被解析，但生成 ABI 代码时整条声明会被丢弃。

**原因**：指针是进程内地址，跨进程/跨语言没有意义。

**替代方案**：

```pascal
// 错误 —— 最终被跳过
function ReadAddr(const p: Pointer): Int64;

// 正确 —— 用 Int64 承载地址
function ReadAddr(const addr: Int64): Int64;

// 更推荐 —— 用 TBytes 承载二进制
function ReadBuffer: TBytes;
```

### 3.5 容易踩的坑

**坑 1：`Integer` 在 C++ 端是 32 位**

```pascal
function GetCount: Integer;
// C++ 端看到的是 std::int32_t，不是 64 位！
```

**如果需要 64 位整数，用 `Int64`**。

**坑 2：`Extended` / `Real` 在 C++ 端降级为 `double`**

```pascal
function Compute(x: Extended): Extended;
// C++ 端是 double，有精度损失
```

**如果需要高精度，用 `Double` 或接受降级**。

**坑 3：JSON 描述里所有整型都写 `int64`，但实际 ABI 代码不一定 64 位**

JSON 描述统一把整型表述为 `int64`，是给 AI 看的语义标签；实际生成的 ABI 代码按上表映射。**要严格 64 位，请写 `Int64`**。

---

## 4. 注释

### 4.1 绑定规则

| 情况 | 是否绑定？ |
|------|:----------:|
| 注释紧贴在声明上方 | ✅ |
| 注释 → 一个或多个空行 → 声明 | ✅ |
| 注释1 → 注释2 → 声明 | ✅（两者都绑定，用换行连接） |
| 声明 → 行尾注释 | ❌ |
| 注释 → 其它非空白 token → 声明 | ❌（被中断） |

```pascal
// 错误 —— 行尾注释被忽略
function Foo: Integer; // 这段文本会丢失

// 正确 —— 前置注释会被绑定
// 这段文本会被捕获
function Bar: Integer;

// 正确 —— 注释和声明之间可以有多个空行
(* 这段文本会被捕获 *)


function Baz: Integer;
```

### 4.2 注释风格 —— 按安全性排序

1. **`(* ... *)`** —— 最安全。正文里的 `*)` 序列很少见，不易与正文冲突。
2. **`// ...`** —— 到行尾结束，不受花括号影响。
3. **`{ ... }`** —— 仅当正文里不含 `}` 时使用。

### 4.3 `}` 陷阱

`{ ... }` 注释的正文里如果含有 `}`，会在**第一个 `}`** 处被截断。**注释会丢失或残缺**。

```pascal
// 错误 —— Comment 会在 "host": 之后被截断
{
  返回配置 JSON。
  示例：{"host": "localhost", "port": 8080}
}
function GetConfig: string;
```

```pascal
// 修复
(*
  返回配置 JSON。
  示例：{"host": "localhost", "port": 8080}
*)
function GetConfig: string;
```

| 注释正文包含 | 结果 |
|--------------|------|
| `{ ... }` 内含 `}` | Comment 截断 |
| `{ ... }` 内含全角 `｝` | OK |
| `(* ... *)` 内含 `}` | OK |
| `(* ... *)` 内含 `*)` | Comment 截断 |

### 4.4 工具描述提取规则

工具链会把注释合并成**单行工具描述**，规则如下：

1. 按换行切分。
2. 跳过空行。
3. 跳过以 `@` 开头的行（Doxygen 标签）。
4. 去掉行首的 `*` 续行标记（最多两次）。
5. **只取第一个非空、非 `@` 段落**。
6. 截断为 **200 字符**。

```pascal
(*
  计算两个整数的和。

  a: 第一个加数
  b: 第二个加数

  @return 两数之和          <- 被跳过（@ 行）

  Return value: a 与 b 的和。
*)
function Add(a, b: Integer): Integer;
```

结果：`计算两个整数的和。`

**⚠️ 只取第一段**——后面的参数描述和 `Return value` 行不会进入工具描述，但**会进入参数描述提取**（见第 5 章）。

**写作建议**：把核心信息放在第一段，第一段尽量在 200 字符内。

### 4.5 多条注释的合并

```pascal
(* 第一行 *)

(* 第二行 *)
function F: Integer;
```

两条注释都会绑定，用换行连接成 `第一行\n第二行` 作为 `Comment`。

---

## 5. 参数描述

### 5.1 行首规则

**参数名必须位于行首**（或直接位于 Doxygen 标签之后）才会被识别为参数描述行。

```pascal
(*
  host: 主机名              <- ✅ 识别为 host 的描述
  port: 端口号              <- ✅ 识别为 port 的描述

  这个配置控制 host 和 port。  <- 行首不是参数名，不会被吸收
*)
function Connect(host: string; port: Integer);
```

### 5.2 支持的形式

```pascal
// 形式 A：name + 冒号
(*
  a: 第一个加数
  b: 第二个加数
*)

// 形式 B：name + 等号
(*
  a = 第一个加数
  b = 第二个加数
*)

// 形式 C：Doxygen @param
(*
  @param a 第一个加数
  @param b 第二个加数
*)

// 形式 D：name + 空白
(*
  a  第一个加数
  b  第二个加数
*)

// 形式 E：Doxygen 立即
(*
  @a 第一个加数
  @b 第二个加数
*)
```

### 5.3 大小写

参数名匹配**大小写不敏感**。

```pascal
(*
  SOURCE: 源文本
*)
function F(Source: string);
// Source.Description = "源文本"
```

### 5.4 多行描述

续行必须比参数名**缩进更深**（严格大于）。

```pascal
(*
  生成代码。

  target: 目标语言，选一个：
            pascal_service   生成 Pascal 服务端
            pascal_call      生成 Pascal 客户端
            python_service   生成 Python 服务端
          <unit> 是归一化后的 UnitName。

  Return value: 生成的代码。
*)
function Generate(target: string): string;
```

`target.Description` =
```
目标语言，选一个：
            pascal_service   生成 Pascal 服务端
            pascal_call      生成 Pascal 客户端
            python_service   生成 Python 服务端
          <unit> 是归一化后的 UnitName。
```

**⚠️ 严格大于**：续行缩进等于声明行缩进时，续行**不会**被累积。

```pascal
(*
  target: 描述
  continuation line         <- 缩进相同，不会被累积
*)
```

```pascal
(*
  target: 描述
    continuation line       <- 缩进更深，会被累积
*)
```

### 5.5 常见误判与修复

**误判 1：自然语言句子恰好以参数名开头**

```pascal
// 问题 —— "host can also be an IP address." 被吸收进 host 的描述
(*
  host: 主机名

  host 也可以是 IP 地址。
*)
function Connect(host: string);
```

**修复**：

```pascal
// 修复 1：反引号包裹
(*
  host: 主机名

  `host` 也可以是 IP 地址。
*)

// 修复 2：加大缩进（变成续行）
(*
  host: 主机名
        也可以是 IP 地址。
*)

// 修复 3：改写句子
(*
  host: 主机名

  该参数也可以是 IP 地址。
*)
```

**误判 2：参数名出现在行中间**

不会被吸收，安全。

```pascal
(*
  host: 主机名
  port: 端口号

  这个配置控制服务使用的主机和端口。   <- 安全，行首不是参数名
*)
```

---

## 6. 返回值

### 6.1 必须写在签名里

**返回类型必须在签名中声明**。只在注释里写会丢失。

```pascal
// 错误 —— 签名无返回类型，解析失败
(*
  @return 两数之和
*)
function Add(a, b: Integer);

// 正确
(*
  Return value: a 与 b 的和。
*)
function Add(a, b: Integer): Integer;
```

### 6.2 类型归一化

| 签名类型 | JSON 描述 | 生成的 Pascal ABI | 生成的 C++ ABI |
|----------|:---------:|:-----------------:|:--------------:|
| 任意整型 | `int64` | 原类型 | 按类型宽度映射 |
| 任意浮点 | `double` | 原类型 | `float` / `double` |
| 任意字符串 | `string` | `string` | `std::string` |
| **`TBytes`** | **`TBytes`** | **二进制负载** | **`std::vector<std::uint8_t>`** |

### 6.3 `procedure` 不要写返回值

`procedure` 无返回值。不要写 `Return value` 行，也不要写 `@return`。

```pascal
// 正确
(*
  记录一条日志。

  msg: 日志内容
*)
procedure Log(const msg: string);

// 错误 —— @return 会被忽略
(*
  @return nothing
*)
procedure Log2(const msg: string);
```

### 6.4 推荐的注释结构

```pascal
(*
  计算两个整数的和。

  a: 第一个加数
  b: 第二个加数

  Return value: a 与 b 的和，类型为 Integer。
*)
function Add(a, b: Integer): Integer;
```

| 行 | 用途 | 进入结构化 JSON？ |
|----|------|:-----------------:|
| `: Integer` | 结构化返回类型 | ✅ |
| `Return value: ...` | 人类 / LLM 可读语义 | ❌ —— 仅注释 |

---

## 7. `TBytes` 二进制负载（v10 新增）

### 7.1 什么时候用 `TBytes`

| 场景 | 推荐类型 |
|------|---------|
| 文本数据（JSON、XML、日志） | `string` |
| 二进制数据（图片、压缩包、序列化数据） | `TBytes` |
| 加密后的数据 | `TBytes` |
| 任意长度的字节序列 | `TBytes` |

**原则**：如果数据的语义是"字节序列"，用 `TBytes`；如果是"文本"，用 `string`。

### 7.2 允许的形式

```pascal
// 参数
procedure SendBytes(const Data: TBytes);
procedure SendBytesArray(const Data: array of Byte);   // 等价 TBytes

// 返回值
function MakeBytes(const n: Integer): TBytes;
function MakeBytesArray: array of Byte;                // 等价 TBytes

// 混合
function TransformBytes(const Data: TBytes): TBytes;
function HashBytes(const Data: TBytes): string;
function CombineBytes(const Prefix: TBytes; Suffix: Byte): TBytes;
```

`TBytes` 与 `array of Byte` 在工具链里**完全等价**——它们会被归一到同一个类型。推荐写 `TBytes`（更清晰）。

### 7.3 禁止的形式

```pascal
// ❌ var / out 修饰的 TBytes
procedure ProcessBytesMutable(var Data: TBytes);
procedure FillBytes(out Data: TBytes);

// ❌ 非字节的动态数组
function Sum(const a: array of Integer): Integer;
function Join(const a: array of string): string;
function Points(const a: array of TPoint): Integer;

// ❌ 静态数组
function ReadAll(const a: array[0..255] of Byte): Integer;

// ❌ Pointer
function ReadRaw(const p: Pointer): TBytes;
```

### 7.4 内存管理（用户视角）

- **作为参数**（`const Data: TBytes`）：**按值传递**。被调方拿到的是数据副本，可以自由使用，不会影响调用方。
- **作为返回值**（`function F: TBytes`）：**归调用方所有**。被调方返回一个 `TBytes`，调用方拿到后就是普通 `TBytes`，引用计数自动管理。
- **跨进程传输**：工具链自动完成序列化/反序列化，**用户无需关心**。

### 7.5 完整示例

```pascal
(*
  发送一段字节序列到指定通道。

  Channel: 通道名
  Data:    要发送的字节序列
*)
procedure SendBytes(const Channel: string; const Data: TBytes);

(*
  生成指定长度的字节序列。

  n: 长度

  Return value: 长度为 n 的 TBytes。
*)
function MakeBytes(const n: Integer): TBytes;

(*
  回显一段字节序列。

  Data: 输入序列

  Return value: 与输入完全相同的序列。
*)
function EchoBytes(const Data: TBytes): TBytes;

(*
  计算字节序列的哈希。

  Data: 输入序列

  Return value: 哈希的十六进制字符串。
*)
function HashBytes(const Data: TBytes): string;

(*
  把一段字节序列拼接到另一个字节序列之后。

  Prefix: 前缀
  Suffix: 单字节后缀

  Return value: 拼接后的 TBytes。
*)
function CombineBytes(const Prefix: TBytes; Suffix: Byte): TBytes;
```

---

## 8. 完整示例

### 8.1 全部被接受

```pascal
unit SampleUnit;

interface

(*
  计算两个整数的和。

  a: 第一个加数
  b: 第二个加数

  Return value: a 与 b 的和。
*)
function Add(a, b: Integer): Integer;

(*
  计算两个整数的积。

  @param a 第一个乘数
  @param b 第二个乘数

  Return value: a 与 b 的积。
*)
function Mul(a, b: Integer): Integer;

(*
  回显字符串。

  s: 要回显的字符串

  Return value: 原样返回。
*)
function Echo(const s: string): string;

(*
  记录一条日志，无返回值。

  msg: 日志内容
*)
procedure Log(const msg: string);

(*
  返回配置 JSON。

  Return value: JSON 字符串。
*)
function GetConfig: string;

(* —— v10 新增：TBytes 二进制负载 —— *)

(*
  发送一段字节序列到指定通道。

  Channel: 通道名
  Data:    要发送的字节序列
*)
procedure SendBytes(const Channel: string; const Data: TBytes);

(*
  生成指定长度的字节序列。

  n: 长度

  Return value: 长度为 n 的 TBytes。
*)
function MakeBytes(const n: Integer): TBytes;

(*
  回显一段字节序列。

  Data: 输入序列

  Return value: 与输入完全相同的序列。
*)
function EchoBytes(const Data: TBytes): TBytes;

(*
  计算字节序列的哈希。

  Data: 输入序列

  Return value: 哈希的十六进制字符串。
*)
function HashBytes(const Data: TBytes): string;

(*
  把一段字节序列拼接到另一个字节序列之后。

  Prefix: 前缀
  Suffix: 单字节后缀

  Return value: 拼接后的 TBytes。
*)
function CombineBytes(const Prefix: TBytes; Suffix: Byte): TBytes;

implementation

end.
```

### 8.2 全部被跳过或损坏

```pascal
unit BadUnit;

interface

procedure Modify(var x: Integer);                  // var
procedure Fill(out y: Integer);                    // out
function  IsEven(x: Integer): Boolean;             // Boolean
function  Sum(const a: array of Integer): Integer; // 非字节数组
function  Wrap<T>(x: T): Integer;                  // 泛型
function  Get(p: Pointer): Integer;                // Pointer
function  Now2: TDateTime;                         // TDateTime
procedure ProcessBytesMutable(var Data: TBytes);   // var 修饰 TBytes

{
  返回配置 JSON。
  示例：{"host": "localhost"}                      // 包含 }，Comment 被截断
}
function GetConfig: string;

(*
  host: 主机名

  host 也可以是 IP 地址。                          // host.Description 被污染
*)
function Connect(host: string);

implementation

function Helper: Integer;                          // 位于 implementation
begin
  Result := 0;
end;

end.
```

---

## 9. 自检清单

```pascal
// 1. 位于 interface 段？
// 2. 顶层（不在 class / record / interface / function 内）？
// 3. 无 var / out 参数？（TBytes 也一样）
// 4. 每个类型都在白名单里？（含 TBytes / array of Byte）
// 5. 注释紧贴声明，或上方只隔空行？
// 6. 若用 { }，正文是否含 }？ 含则换 (* ... *)。
// 7. function 是否有 : T 返回类型？procedure 是否没有 :？
// 8. 每个参数描述是否位于行首？
// 9. 多行描述续行是否缩进更深？
// 10. 第一段注释是否在前 200 字符内包含核心信息？
```

| # | 检查项 | 失败时如何处理 |
|:-:|--------|----------------|
| 1 | 位于 interface 段？ | 上移 |
| 2 | 顶层？ | 移到顶层 |
| 3 | 无 `var` / `out`？ | 用 `const` + 返回值 |
| 4 | 类型在白名单？ | 改用整型 / 浮点 / 字符串 / `TBytes` |
| 5 | 注释在上方？ | 把注释移到上方 |
| 6 | `{ }` 内无 `}`？ | 改用 `(* ... *)` |
| 7 | `function` 有 `: T`？ | 补上返回类型 |
| 8 | 参数名在行首？ | 把名字移到行首 |
| 9 | 续行缩进更深？ | 加大缩进 |
| 10 | 第一段简短？ | 精简第一段 |

---

## 10. 最小模板

### 10.1 标量签名模板

```pascal
unit MyUnit;

interface

(*
  <一句话描述函数用途。>

  a: <a 的描述>
  b: <b 的描述>

  Return value: <返回什么>。
*)
function MyFunc(a: Integer; b: string): Integer;

implementation

function MyFunc(a: Integer; b: string): Integer;
begin
  Result := 0;
end;

end.
```

### 10.2 `TBytes` 签名模板

```pascal
unit MyBytesUnit;

interface

(*
  <一句话描述函数用途。>

  Data: <输入字节序列的描述>

  Return value: <返回的字节序列的描述>。
*)
function TransformBytes(const Data: TBytes): TBytes;

implementation

function TransformBytes(const Data: TBytes): TBytes;
begin
  // 示例：原样返回
  Result := Data;
end;

end.
```

**应当做**：

- 用 `(* ... *)` 写注释。
- 把参数描述放在一个块里，**参数名从行首开始**。
- 返回类型写在签名里（`function F: Integer` / `function F: TBytes`）。
- 续行比参数名缩进更深。
- 用 `TBytes` 承载二进制负载。
- 需要 64 位整数时写 `Int64`，不要写 `Integer`。

**不应当做**：

- 使用 `var` / `out`（包括 `var Data: TBytes`）。
- 使用 `Boolean`、非字节动态数组、record、class、指针、`TDateTime`。
- 依赖 `@return` 提供返回类型。
- 在 `{ }` 注释里写 `}`。
- 把 `TBytes` 当成 `array of Integer`——只有字节数组被支持。
- 在 `implementation` 段声明需要导出的函数。

---

## 11. 快速查表

| 症状 | 原因 | 修复方式 |
|------|------|----------|
| 声明从 JSON 中消失 | 不是顶层 / 不在 interface 段 | 移动它 |
| 声明从 JSON 中消失 | `var` / `out` 参数 | 用 `const` + 返回值 |
| 声明从 JSON 中消失 | 类型不在白名单 | 改用整型 / 浮点 / 字符串 / `TBytes` |
| 声明从 JSON 中消失 | `function` 缺少 `: T` | 补上返回类型 |
| 声明从 JSON 中消失 | 泛型 / 枚举 / record / class / 指针 / `TDateTime` | 换成白名单类型 |
| 声明从 JSON 中消失 | `var` 修饰 `TBytes` | 改用 `const Data: TBytes` 并返回新的 `TBytes` |
| 声明从 JSON 中消失 | `implementation` 段的函数 | 移到 `interface` 段 |
| 声明从 JSON 中消失 | 嵌套在 class / record / interface 内 | 移到顶层 |
| `Comment` 被截断 | `{ }` 注释里含 `}` | 改用 `(* ... *)` |
| `Comment` 为空 | 注释和声明之间隔了非空白 token | 移除中间的 token |
| 工具描述为空 | 注释只有 `@param` / `@return` 行 | 加一段自由文本 |
| 工具描述被截断 | 第一段超过 200 字符 | 精简第一段 |
| LLM 不知道返回类型 | 只写在注释里 | 在签名中补 `: T` |
| 参数描述缺失 | 名字不在行首 | 把名字移到行首 |
| 参数描述被污染 | 自然语言句子恰好以参数名开头 | 改写句子 / 反引号包裹 / 加大缩进 |
| 多行描述被截断 | 续行缩进未比参数名深 | 加大续行缩进 |
| **`TBytes` 参数被跳过** | **误用了 `array of Integer` / `array of string`** | **改为 `TBytes` 或 `array of Byte`** |
| **`TBytes` 返回被跳过** | **签名写成 `array of Integer` 等** | **改为 `function F: TBytes`** |
| **`Pointer` 参数被跳过** | **`Pointer` 不在最终生成白名单** | **改用 `Int64` 承载地址，或改用 `TBytes`** |
| **`Integer` 在 C++ 端是 32 位** | **C++ 生成器按 32 位映射** | **如果需要 64 位，用 `Int64`** |
| **`Extended` / `Real` 精度损失** | **C++ 端降级为 `double`** | **改用 `Double`，或接受精度损失** |
| 重名函数被自动重命名 | 工具链自动去重 | 正常行为（`Foo` → `Foo1`） |
| JSON 往返后源码位置丢失 | 序列化不包含位置信息 | 正常行为 |

---

## 12. 设计原则

这些规则不是随意定的，背后有清晰的语义约束：

1. **仅顶层**。ABI 工具链只关心单元的公开接口。class / record / interface 内的声明属于内部实现，implementation 段属于单元私有——它们没有跨语言导出的意义。

2. **仅值类型**。跨进程/跨语言通信只能传递值。`var` / `out` 依赖进程内引用，跨进程时无意义。

3. **仅可序列化类型**。ABI 层需要在不同语言间序列化数据。能序列化的只有：整数、浮点、字符串、字节序列。其它类型（布尔、枚举、record、class、指针、时间）在不同语言中表示不一致，无法保证正确传输。

4. **`TBytes` 是字节序列的一等公民**。跨语言的二进制负载统一用字节序列表达。`array of Byte` 与 `TBytes` 等价；其它动态数组不被支持，因为元素类型的跨语言表示无法保证一致。

5. **结构化注释**。注释是 AI 理解声明的唯一途径。规则（行首、缩进、`}` 陷阱）都是为了让注释能被可靠解析，而不是让用户为难。

6. **返回类型来自签名**。签名是结构化的，注释是非结构化的。结构化信息优先——返回类型必须写在签名里，注释只提供人类可读的描述。

7. **静默跳过**。工具链的设计哲学是"能解析就解析，不能解析就跳过"——不会因为一条声明不合法就让整个单元失败。但这也意味着错误容易被忽视，所以需要这份文档把规则说清楚。

8. **第一段是工具描述**。AI 拿到的工具描述是单行、200 字符内的文本。把核心信息放在第一段，是对 AI 读者的尊重。

---

## 13. 修订记录

- **v10.0** —— 基于 ABI 生成器行为重建。新增 `TBytes` / `array of Byte` 白名单支持。补充完整的跨语言类型映射表。明确 `Pointer` 最终被拒绝、`Integer` 在 C++ 端是 32 位、`Extended`/`Real` 在 C++ 端降级为 `double`。补充 `TBytes` 的参数/返回值语义与内存管理说明。明确工具描述只取第一段。中文全文重写，面向编写者而非源码读者。
- **v9.0** —— 精简版。示例优先。
- **v8.0** —— 加入缩进感知的参数描述规则。
- **v7.0** —— 加入返回类型归一化、工具描述拼接规则。
- **v6.0** —— 加入返回值注释指引。
- **v5.0** —— 加入 `{ }` 闭花括号陷阱。
- **v4.0** —— 白名单与空行规则。

**本文档是编写契约。按本文写，声明就能被正确提取、归一化、生成；不按本文写，声明会被静默跳过。**