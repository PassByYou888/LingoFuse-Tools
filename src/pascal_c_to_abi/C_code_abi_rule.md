# C 声明编写规则（ABI 工具链）

**定位**：这是一份**编写指南**，不是源码解读。按本文写，声明就能被正确提取并生成；不按本文写，声明会被**静默跳过**（无错误、无警告，只在报告里留一行原因）。
**契约**：本文档是**解析契约**。偏离契约会导致声明被静默跳过、注释被静默丢弃、参数描述被静默丢失。

---

## 0. 30 秒速览

### 0.1 能写什么

```c
/* 位于头文件顶层的函数原型（以 ; 结尾） */
int add(int a, int b);
unsigned int get_count(void);
const char * get_error(int code);

/* v10 新增：CBytes 二进制负载 */
void send_bytes(const char * channel, CBytes data);
CBytes make_bytes(int n);
CBytes echo_bytes(CBytes data);

/* extern "C" 块是透明的，内部内容正常解析 */
extern "C" {
    int mul(int a, int b);
}
```

### 0.2 不能写什么

```c
/* 都会被静默跳过 */
int helper(void) { return 42; }                  /* 函数定义（有函数体） */
void set_cb(void (*cb)(int));                    /* 函数指针参数 */
double dist(struct Point p1, struct Point p2);   /* struct 参数 */
int set_color(enum Color c);                     /* enum 参数 */
_Bool is_even(int x);                            /* bool 返回 */
void * allocate(int size);                       /* 非 char 指针 */
void fill(int * p);                              /* 非 char 指针 */
int fill_buffer(int buf[], int len);             /* 非字节数组，数组语义会丢失 */
void matrix(int m[][10], int rows);              /* 多维数组 */
int printf_like(const char * fmt, ...);          /* 可变参数 */
int global_counter;                              /* 全局变量 */
struct Point { int x; int y; };                  /* 类型定义 */
#include <stdio.h>                               /* 预处理 */
```

### 0.3 内容流向

| 你写的内容 | 去向 |
|------------|------|
| 签名（参数名、类型、返回类型） | 结构化 JSON（`Name`、`Params[i].Name`、`Params[i].Typ`、`ReturnType`） |
| 紧邻的注释 | `Comment` 字段；第一段非空非 `@` 段落 → 工具描述（截断 200 字符） |
| 注释里的 `@param name desc` 行 | `Params[i].Description` |
| 注释里的 `@return` | 只保留在 `Comment` 里，**不进入**结构化 JSON |
| 注释里的 `Return value: ...` | 只保留在 `Comment` 里，**不进入**结构化 JSON |

**AI 实际能看到的只有两样东西**：`Comment`（工具描述 + 参数描述）、`ReturnType`。其它内容不进 JSON。

---

## 1. 位置

### 1.1 规则

必须是头文件中的**顶层函数原型**，以 `;` 结尾。

- 不能有函数体（`{ ... }`）。
- 不能嵌套在 `struct` / `union` / `enum` / `typedef` 里。
- 不能是全局变量或宏。

### 1.2 头文件必须的结构

工具链会扫描整个头文件。头文件的第一行注释、include guard、函数原型，都会参与解析。

**推荐结构**：

```c
/* foo.h */
#ifndef FOO_H
#define FOO_H

#include <stddef.h>

/* 函数原型 */
int add(int a, int b);

#endif /* FOO_H */
```

**头文件第一行的注释和 include guard 决定"单元名"**（见第 2 章）。这不是可选项——缺少它们会导致生成的 Pascal 单元名是 `untitled.h`，而 `untitled.h` 是**非法 Pascal 单元名**。

### 1.3 哪些位置不被接受

| 位置 | 结果 | 修复 |
|------|------|------|
| 函数体内 | 跳过 | 移到顶层 |
| `struct` / `union` / `enum` / `typedef` 内部 | 跳过 | 移到顶层 |
| `#define` 宏 | 跳过 | 改为函数原型 |
| 全局变量 | 跳过 | 改为 getter/setter 函数 |
| 函数定义（有 `{ ... }`） | 跳过 | 去掉函数体 |
| 多维数组参数 | 整条声明跳过 | 改为单维数组或 CBytes |

---

## 2. 单元名

### 2.1 规则

**单元名决定了生成的 Pascal 单元名**。如果单元名是 `untitled.h`，Pascal 生成器会输出 `unit untitled.h;`——**这是非法 Pascal**，编译会失败。

所以：**头文件必须让工具链能提取出合法的单元名**。

### 2.2 提取优先级

工具链在前 100 行内按以下优先级提取单元名：

1. **`.h` / `.H` / `.c` / `.C` 文件名**（`/* foo.h */` → `foo`）。
2. **Include guard 宏名**（`#ifndef FOO_H` → `FOO`）。
3. **回退**：`untitled.h`。

**⚠️ `.hpp` / `.hxx` 不被识别为文件名后缀**。如果文件是 `foo.hpp`，且没有 include guard，单元名会退化为 `untitled.h`。

### 2.3 Include guard 的后缀剥离规则

工具链识别并剥离以下后缀（按长度从长到短）：

```
_INCLUDED、_HXX、_HPP、_H__、_H_、_H
```

然后剥离首尾的下划线。

| 原始宏名 | 剥离后 |
|----------|--------|
| `FOO_H` | `FOO` |
| `FOO_H_` | `FOO` |
| `__FOO_H__` | `FOO` |
| `FOO_INCLUDED` | `FOO` |
| `FOO_HPP` | `FOO` |
| `FOO_HXX` | `FOO` |
| `MAX_SIZE` | `untitled.h`（不是 guard） |

### 2.4 推荐写法

```c
/* foo.h */
#ifndef FOO_H
#define FOO_H

/* 函数原型 */
int add(int a, int b);

#endif /* FOO_H */
```

单元名会被提取为 `foo`（优先文件名），Pascal 单元名是 `foo_abi_service_unit`——**合法**。

### 2.5 禁止的写法

```c
/* 1.0.3.h */          // 文件名以数字开头，不是合法标识符
#ifndef 1_0_3_H       // 宏名不是合法标识符
#define MAX_SIZE 1024  // MAX_SIZE 不是 guard（无 _H 后缀）
```

单元名会退化为 `untitled.h`。生成 Pascal 代码时，`unit untitled.h;` 编译失败。

### 2.6 紧急修复

如果头文件已经无法提供合法单元名，在生成前手动改：

```
把"untitled.h"改为合法标识符（如"myunit"）
```

不同生成器入口的修复方式不同，但**根因是头文件缺少合法的文件名或 guard**。最好的修复是**写头文件时就提供正确的 guard**。

---

## 3. 预处理与块

### 3.1 预处理指令

**所有 `#` 开头的行都会被跳过**——包括 `#include`、`#define`、`#if`、`#ifdef`、`#ifndef`、`#endif`、`#pragma`。

```c
#include <stdio.h>                       /* 跳过 */
#define MAX_SIZE 1024                    /* 跳过 */
#pragma once                             /* 跳过 */
#ifndef FOO_H                            /* 跳过 */
#define FOO_H                            /* 跳过 */
#endif                                   /* 跳过 */
```

**但 include guard 的宏名会被用于提取单元名**（见第 2 章）。

### 3.2 `extern "C"` 块

`extern "C" { ... }` 是**透明的**。内部的函数原型会被正常解析。

```c
extern "C" {
    int mul(int a, int b);               /* 会被提取 */
    int divi(int a, int b);              /* 会被提取 */
}
```

**判定条件**：`{` 前不是 `)`，且语句内不包含 `struct` / `enum` / `union` / `typedef`。

### 3.3 类型定义块

`struct` / `union` / `enum` / `typedef` 的 `{ ... }` 块会被**整体跳过**。

```c
struct Point { int x; int y; };          /* 整体跳过 */
enum Color { RED, GREEN, BLUE };         /* 整体跳过 */
typedef struct { int v; } TValue;        /* 整体跳过 */
```

### 3.4 函数体

`{ ... }` 前一个是 `)`，说明这是函数定义，**整体跳过**。

```c
int helper(void) { return 42; }          /* 整体跳过 */
```

### 3.5 注释

注释会被跳过，但**前置注释会被绑定到函数原型**（见第 9 章）。

---

## 4. 参数修饰符

### 4.1 规则

| 修饰符 | 是否允许？ | 说明 |
|--------|:----------:|------|
| （无） | ✅ | 值传递 |
| `const` | ✅ | 保留 |
| `restrict` / `__restrict` / `__restrict__` | ✅ | **静默剥离**（不影响功能） |
| `volatile` / `__volatile` / `__volatile__` | ✅ | 保留在类型文本中 |
| `var` / `out` | ❌ | 整条声明被跳过（防御性检查，C 里本来就没有这两个） |

### 4.2 示例

```c
/* OK */
int add(int a, int b);
int mul(const int a, const int b);
int echo(const char * s);

/* const 的位置变体都能识别 */
int f1(const char * s);                  /* const 在前缀 */
int f2(char const * s);                  /* const 在后缀 */
int f3(int * const p);                   /* const 在指针后（但不推荐，见 5.4） */

/* restrict 会被剥离 */
int memcpy_opt(void * restrict dst, const void * restrict src, size_t n);
/* 等价于：int memcpy_opt(void * dst, const void * src, size_t n); */
/* 但 src 会因 void * → Pointer 被拒绝，见 5.3 */
```

### 4.3 多参数共享修饰符

C 里**没有**"多参数共享修饰符"的语法。每个参数必须独立标注：

```c
/* 正确 */
int group_const(const int a, const int b, const int c);

/* 错误（C 语法错误） */
int group_const(const int a, b, c);
```

### 4.4 `const` 在多参数中的注意事项

`const int * p` 和 `int * const p` 语义不同：

- `const int * p`：指针指向的内容是 const，指针本身可变 → 类型文本 `const int *` → 含 `*` → `Pointer` → 被拒绝。
- `int * const p`：指针本身是 const，指向的内容可变 → 类型文本 `int * const` → 含 `*` → `Pointer` → 被拒绝。

两者都因为含 `*` 且不是 `char *` 家族而被拒绝。**`const` 不能拯救指针**。

---

## 5. 类型规则

### 5.1 允许的类型（四大类）

| 类别 | C 类型 |
|------|--------|
| 有符号整型 | `signed char`、`short`、`short int`、`signed short`、`signed short int`、`int`、`signed`、`signed int`、`long`、`long int`、`signed long`、`signed long int`、`long long`、`long long int`、`signed long long`、`signed long long int`、`int8_t`、`int16_t`、`int32_t`、`int64_t` |
| 无符号整型 | `unsigned char`、`unsigned short`、`unsigned short int`、`unsigned int`、`unsigned`、`unsigned long`、`unsigned long int`、`unsigned long long`、`unsigned long long int`、`uint8_t`、`uint16_t`、`uint32_t`、`uint64_t` |
| 指针宽度整型 | `size_t`、`uintptr_t`、`ssize_t`、`ptrdiff_t`、`intptr_t` |
| 浮点 | `float`、`double`、`long double` |
| 字符串 | `char *`、`const char *`、`char const *`、`const char * const`、`char const * const`（含无空格变体） |
| 二进制 | **`CBytes` / `cbytes`**（含 `const cbytes`、`cbytes *`、`const cbytes *`） |
| void（返回） | `void` |

### 5.2 跨语言映射表

| 你写的 C 类型 | Pascal 类型 | JSON 描述 | 生成的 Pascal ABI | 生成的 C++ ABI |
|---------------|:-----------:|:---------:|:-----------------:|:--------------:|
| `signed char` / `int8_t` | `ShortInt` | `int64` | `ShortInt` | `std::int8_t` |
| `short` / `int16_t` | `SmallInt` | `int64` | `SmallInt` | `std::int16_t` |
| `int` / `int32_t` | `Integer` | `int64` | `Integer` | `std::int32_t` |
| `long` / `long int` | `LongInt` | `int64` | `LongInt` | `std::int32_t` |
| `long long` / `int64_t` | `Int64` | `int64` | `Int64` | `std::int64_t` |
| `unsigned char` / `uint8_t` | `Byte` | `int64` | `Byte` | `std::uint8_t` |
| `unsigned short` / `uint16_t` | `Word` | `int64` | `Word` | `std::uint16_t` |
| `unsigned int` / `uint32_t` | `Cardinal` | `int64` | `Cardinal` | `std::uint32_t` |
| `unsigned long` | `LongWord` | `int64` | `LongWord` | `std::uint32_t` |
| `unsigned long long` / `uint64_t` | `UInt64` | `int64` | `UInt64` | `std::uint64_t` |
| `size_t` / `uintptr_t` | `UInt64` | `int64` | `UInt64` | `std::uint64_t` |
| `ssize_t` / `ptrdiff_t` / `intptr_t` | `Int64` | `int64` | `Int64` | `std::int64_t` |
| `float` | `Single` | `double` | `Single` | `float` |
| `double` | `Double` | `double` | `Double` | `double` |
| `long double` | `Extended` | `double` | `Extended` | `double`（精度损失） |
| `char *` 家族 | `string` | `string` | `string` | `std::string` |
| **`CBytes` / `cbytes`** | **`TBytes`** | **`TBytes`** | **二进制负载** | **`std::vector<std::uint8_t>`** |
| `void`（返回） | — | — | 降级为 procedure | 返回类型为 `void` |
| 其它含 `*` | `Pointer` | — | ❌ 被拒绝 | ❌ 被拒绝 |
| 其它任何类型 | — | — | ❌ 被拒绝 | ❌ 被拒绝 |

### 5.3 禁止的类型及原因

以下任意一种都会导致**整条声明被跳过**。

| 类别 | 示例 | 为什么不行 | 替代 |
|------|------|------------|------|
| 布尔 | `bool`、`_Bool` | 跨语言布尔表示不一致 | `int`（0/1）或 `unsigned char` |
| 宽字符 | `wchar_t`、`char16_t`、`char32_t` | 跨语言表示不一致 | `char *` 或 `CBytes` |
| Struct | `struct Point` | 跨语言布局不一致 | 拆成多个标量参数，或 `CBytes` |
| Union | `union Value` | 跨语言布局不一致 | 拆成多个标量参数 |
| Enum | `enum Color` | 跨语言枚举表示不一致 | `int` |
| 自定义 typedef | `TMyHandle` | 无法识别 | 展开为具体类型 |
| **非 char 指针** | `void *`、`int *`、`const void *` | 地址跨进程无意义 | `uint64_t`（承载地址）或 `CBytes` |
| **非字节数组** | `int buf[]`、`double vals[]` | 数组语义最终会丢失 | `CBytes` |
| **多维数组** | `int m[][10]` | 无法序列化 | `CBytes` 或展开为多个参数 |
| 函数指针参数 | `void (*cb)(int)` | 无法序列化 | `uint64_t`（承载句柄） |
| 可变参数 | `...` | 参数个数不定 | 固定参数或 `CBytes` |

### 5.4 指针的三层陷阱（重要）

指针在 C 端会经过**三层过滤**：

```
Fill_C 解析  →  Translate 类型映射  →  Model 归一化
   ✅              部分映射            ❌ 拒绝
```

**唯一被接受的指针是 `char *` 家族**。其他所有指针（`void *`、`int *`、`struct X *` 等）都会被映射为 `Pointer`，然后在 Model 层被拒绝。

**这意味着**：

```c
/* 错误 —— 最终被跳过 */
void * allocate(int size);
void   fill(void * dst, size_t n);
int    read(int * p);
void   use_ptr(struct Point * p);

/* 正确 —— 用 uint64_t 承载地址 */
uint64_t allocate(int size);
void     fill(uint64_t dst, size_t n);
int      read(uint64_t p);
void     use_ptr(uint64_t p);

/* 更推荐 —— 用 CBytes 承载二进制 */
CBytes allocate(int size);
void   fill(CBytes dst, size_t n);
CBytes read(CBytes p);
```

### 5.5 `char *` 家族的边界

`char *` 家族的完整清单：

```c
char *
char*
const char *
const char*
char const *
char const*
const char * const
const char* const
char const * const
char const* const
```

**不在清单中的形式会被映射为 `Pointer` 然后被拒绝**：

```c
/* 被拒绝 —— 不在 char * 家族清单中 */
char * const p1;        // 带指针后 const，不在清单
char * restrict p2;     // restrict 会被剥离，但剥离后是 char *，OK
int * p3;               // int 不是 char
void * p4;              // void 不是 char
```

### 5.6 指针与数组的误区

C 里 `char *` 和 `char []` 参数经常互用。工具链里：

- `char * s` → `string`（OK）
- `char s[]` → `string` 吗？**不是**——会走数组路径（见第 6 章）。

**推荐**：用 `char *` 表达字符串，用 `CBytes` 表达二进制。**不要**用 `char []` 参数。

---

## 6. 数组参数

### 6.1 规则

C 数组参数在工具链里分为**两种命运**：

| 写法 | 结果 | 可靠性 |
|------|------|:------:|
| `unsigned char buf[]` / `uint8_t buf[]` | → `CBytes` | ✅ 可靠 |
| `unsigned char buf[16]` | → `CBytes`（长度信息丢失） | ✅ 可靠 |
| `int buf[]` | → `int`（**数组语义丢失**） | ❌ 不可靠 |
| `int buf[16]` | → `int`（**数组语义丢失**） | ❌ 不可靠 |
| `int m[][10]` | 整条声明被跳过 | ❌ 拒绝 |

**结论**：**只有 `unsigned char []` / `uint8_t []` / `CBytes` 能可靠表达数组**。其他类型的数组最终都会丢失数组语义。

### 6.2 为什么 `int buf[]` 不可靠

工具链的处理流程：

1. `Fill_C` 阶段：识别为 `param_typ='int'`, `param_array='[]'`。
2. `Translate` 阶段：`int` → `Integer`；`param_array` 保留（因为不是 `Byte`）。
3. `Model` 归一化阶段：`Integer` → `int64`（或 `integer`）；**`param_array` 信息在这一层被忽略**。
4. 生成器阶段：按 `int64` 生成单个标量参数。

**结果**：`void fill(int buf[])` 在 ABI 层变成 `void fill(std::int64_t buf)`——`buf` 从数组变成单个整数。

**这是最危险的静默陷阱**——声明看起来合法，但生成结果完全不符合预期。

### 6.3 正确写法

```c
/* 错误 —— 数组语义丢失 */
void fill(int buf[]);
void write_block(int buf[16], int n);

/* 正确 —— 用 CBytes */
void fill(CBytes buf);
void write_block(CBytes buf, int n);

/* 正确 —— unsigned char [] 也可用 */
void fill(unsigned char buf[]);
void write_block(unsigned char buf[16], int n);

/* 正确 —— 用多个标量参数 */
void fill(int b0, int b1, int b2, int b3);
```

### 6.4 多维数组

```c
/* 整条声明被跳过 */
void matrix(int m[][10], int rows);
```

**替代方案**：

```c
/* 展开为一维 CBytes */
void matrix(CBytes m, int rows, int cols);
```

---

## 7. 函数指针参数

### 7.1 规则

函数指针参数会导致**整条声明被跳过**。

```c
/* 整条声明被跳过 */
void set_callback(void (*cb)(int));
void register_handler(int (*handler)(void *, int));
void use_op(double (*op)(double, double));
```

**原因**：函数指针无法序列化。跨进程/跨语言时，指针没有意义。

### 7.2 替代方案

**方案 1：整数句柄**

```c
/* 用 uint64_t 承载句柄 */
void set_callback(uint64_t cb_handle);
void register_handler(uint64_t handler_handle);
```

调用方在本地维护"句柄 → 函数"的映射，ABI 层只传句柄。

**方案 2：字符串标识**

```c
/* 用字符串标识回调 */
void set_callback(const char * callback_id);
```

**方案 3：独立的回调 API**

把回调语义拆成两个独立 API：

```c
/* 注册 */
void register_handler(const char * handler_id);

/* 触发（内部调用注册的 handler） */
int invoke_handler(const char * handler_id, CBytes data);
```

---

## 8. 可变参数

### 8.1 规则

`...` 会导致**整条声明被跳过**。

```c
/* 整条声明被跳过 */
int printf_like(const char * fmt, ...);
void log(const char * level, const char * fmt, ...);
```

**原因**：参数个数和类型在编译时不确定，无法序列化。

### 8.2 替代方案

**方案 1：固定参数**

```c
/* 固定为几个参数 */
void log3(const char * level, const char * fmt, const char * a, const char * b);
```

**方案 2：CBytes 打包**

```c
/* 用 CBytes 承载序列化后的参数 */
void log(const char * level, const char * fmt, CBytes args);
```

**方案 3：数组 + 计数**

```c
/* 用固定上限的数组 + 计数 */
void log(const char * level, const char * fmt, const char ** args, int argc);
/* 注意：const char ** 会被拒绝（不是 char * 家族），应改为 CBytes 或多参数 */
```

---

## 9. 注释

### 9.1 绑定规则

| 情况 | 是否绑定？ |
|------|:----------:|
| 注释紧贴在声明上方 | ✅ |
| 注释 → 一个或多个空行 → 声明 | ✅ |
| 注释1 → 注释2 → 声明 | ✅（两者都绑定） |
| 声明 → 行尾注释 | ❌ |
| 注释 → 其它非空白 token → 声明 | ❌（被中断） |

```c
/* 错误 —— 行尾注释被忽略 */
int foo(void); /* 这段文本会丢失 */

/* 正确 —— 前置注释会被绑定 */
/* 这段文本会被捕获 */
int bar(void);
```

### 9.2 注释风格

三种风格都支持：

1. **`/* ... */`** —— 块注释。
2. **`// ...`** —— 行注释。
3. **`/** ... */`** —— Doxygen 风格块注释（推荐）。

### 9.3 多行注释的规范化

工具链会对多行块注释做规范化：

- 第一行原样保留。
- 后续行如果已带 `*` 前缀，会归一为 ` * <内容>`。
- 后续行如果已带 `/` 前缀（罕见），原样保留。
- 普通文本行会加 ` * ` 前缀。
- 空行保持空行（但连续 `#10` 会被合并）。

**示例**：

```c
/**
 * Computes the sum of two integers.
 * @param a first addend
 * @param b second addend
 * @return the sum
 */
int add(int a, int b);
```

规范化后的 `Comment`：
```
/**
 * Computes the sum of two integers.
 * @param a first addend
 * @param b second addend
 * @return the sum
 */
```

或者对于更简单的写法：

```c
/*
   Computes the sum.
   Returns an int.
*/
int add(int a, int b);
```

规范化后的 `Comment`：
```
/*
 * Computes the sum.
 * Returns an int.
 */
```

### 9.4 工具描述提取规则

工具链会把注释合并成**单行工具描述**，规则如下：

1. 按换行切分。
2. 跳过空行。
3. 跳过以 `@` 开头的行（Doxygen 标签）。
4. 去掉行首的 `*` 续行标记（最多两次）。
5. **只取第一个非空、非 `@` 段落**。
6. 截断为 **200 字符**。

```c
/**
 * Computes the sum of two integers.
 * @param a first addend
 * @param b second addend
 * @return the sum
 * Return value: an Integer representing the sum.
 */
int add(int a, int b);
```

结果：`Computes the sum of two integers.`

**⚠️ 只取第一段**——后面的 `@param` 和 `Return value` 行不会进入工具描述，但**会进入参数描述提取**（见第 10 章）。

**写作建议**：把核心信息放在第一段，第一段尽量在 200 字符内。

---

## 10. 参数描述

### 10.1 行首规则

**参数名必须位于行首**（或直接位于 Doxygen 标签之后）才会被识别为参数描述行。

```c
/**
 * Computes the sum.
 *
 * a: first addend
 * b: second addend
 *
 * This function is used in many places.
 */
int add(int a, int b);
```

**`a:` 和 `b:` 在行首**（忽略 ` * ` 前缀后），会被识别为参数描述。`This function is used in many places.` 在行首不是参数名，不会被吸收。

### 10.2 支持的形式

```c
/* 形式 A：name + 冒号 */
/**
 * a: first addend
 * b: second addend
 */

/* 形式 B：name + 等号 */
/**
 * a = first addend
 * b = second addend
 */

/* 形式 C：Doxygen @param */
/**
 * @param a first addend
 * @param b second addend
 */

/* 形式 D：name + 空白 */
/**
 * a  first addend
 * b  second addend
 */

/* 形式 E：Doxygen 立即 */
/**
 * @a first addend
 * @b second addend
 */

/* 形式 F：Doxygen 关键字变体 */
/**
 * \arg a first addend
 * \parameter b second addend
 */
```

**支持的分隔符**：`:`、`=`、全角 `：`、全角 `＝`。

### 10.3 大小写

参数名匹配**大小写不敏感**。

```c
/**
 * SOURCE: source text
 */
int f(const char * Source);
/* Source.Description = "source text" */
```

### 10.4 多行描述

续行必须比参数名**缩进更深**（严格大于）。

```c
/**
 * Generates code.
 *
 * target: target language, pick one:
 *           pascal_service   generate Pascal service
 *           pascal_call      generate Pascal call
 *           python_service   generate Python service
 *         <unit> is the normalized UnitName.
 *
 * Return value: the generated code.
 */
int generate(const char * target);
```

`target.Description` =
```
target language, pick one:
           pascal_service   generate Pascal service
           pascal_call      generate Pascal call
           python_service   generate Python service
         <unit> is the normalized UnitName.
```

**⚠️ 严格大于**：续行缩进等于声明行缩进时，续行**不会**被累积。

### 10.5 常见误判与修复

**误判 1：自然语言句子恰好以参数名开头**

```c
/* 问题 —— "host can also be an IP address." 被吸收进 host 的描述 */
/**
 * host: host name
 *
 * host can also be an IP address.
 */
int connect(const char * host);
```

**修复**：

```c
/* 修复 1：反引号包裹 */
/**
 * host: host name
 *
 * `host` can also be an IP address.
 */

/* 修复 2：加大缩进（变成续行） */
/**
 * host: host name
 *       can also be an IP address.
 */

/* 修复 3：改写句子 */
/**
 * host: host name
 *
 * The parameter can also be an IP address.
 */
```

**误判 2：参数名出现在行中间**

不会被吸收，安全。

```c
/**
 * host: host name
 * port: port number
 *
 * This config controls the host and port used by the service.
 */
int connect(const char * host, int port);
```

---

## 11. 返回值

### 11.1 必须写在签名里

**返回类型必须在签名中声明**。只在注释里写会丢失。

```c
/* 错误 —— 没有签名返回类型（C 里不可能，但概念上说明问题） */
/* 注：C 里每个函数必须有返回类型，所以这条规则在 C 端自然满足 */

/* 正确 */
int add(int a, int b);
```

**C 端与 Pascal 端的差异**：C 的语法要求每个函数必须有返回类型，所以"返回类型丢失"在 C 端不会发生。但 `void` 返回需要特别注意：

### 11.2 `void` 返回

```c
/* 生成 procedure（无返回值） */
void log(const char * msg);
void send_bytes(const char * channel, CBytes data);
```

`void` 返回会被**降级为 procedure**——生成代码里没有返回值。

### 11.3 `const` 返回

```c
/* const 返回类型 —— ResultMod='const' */
const char * get_name(void);
```

`const` 会在两个地方体现：

1. `ResultDecl = 'const char *'`（保留原始文本）。
2. `ResultMod = 'const'`（作为修饰符）。

**⚠️ 副作用**：生成 C 代码时，可能出现双重 `const`：

```c
/* 输入 */
const char * get_name(void);

/* 生成的 C 代码（可能出现） */
const const char * get_name(void);
```

这个双重 `const` 在某些编译器下会报错。**如果目标语言是 C，避免在返回类型上写 `const`**——用 `char *` 即可。

### 11.4 推荐写法

```c
/**
 * Gets the error message.
 *
 * code: error code
 *
 * Return value: error description string.
 */
const char * get_error_message(int code);
```

但**如果目标是 C**，改为：

```c
/**
 * Gets the error message.
 *
 * code: error code
 *
 * Return value: error description string.
 */
char * get_error_message(int code);
```

---

## 12. 完整示例

### 12.1 全部被接受

```c
/* sample.h */
#ifndef SAMPLE_H
#define SAMPLE_H

#include <stddef.h>

/**
 * Computes the sum of two integers.
 *
 * a: first addend
 * b: second addend
 *
 * Return value: the sum of a and b.
 */
int add(int a, int b);

/**
 * Computes the product of two integers.
 *
 * @param a first multiplicand
 * @param b second multiplicand
 *
 * Return value: the product of a and b.
 */
int mul(const int a, const int b);

/**
 * Echoes a string.
 *
 * s: string to echo
 *
 * Return value: the same string.
 */
const char * echo(const char * s);

/**
 * Logs a message. No return value.
 *
 * msg: log content
 */
void log(const char * msg);

/**
 * Returns the configuration JSON.
 *
 * Return value: a JSON string.
 */
const char * get_config(void);

/* —— v10 新增：CBytes 二进制负载 —— */

/**
 * Sends a byte sequence to the given channel.
 *
 * channel: channel name
 * data:    byte sequence to send
 */
void send_bytes(const char * channel, CBytes data);

/**
 * Makes a byte sequence of the given length.
 *
 * n: length
 *
 * Return value: a CBytes of length n.
 */
CBytes make_bytes(int n);

/**
 * Echoes a byte sequence.
 *
 * data: input sequence
 *
 * Return value: the same sequence.
 */
CBytes echo_bytes(CBytes data);

/**
 * Computes the hash of a byte sequence.
 *
 * data: input sequence
 *
 * Return value: hash as a hex string.
 */
char * hash_bytes(CBytes data);

/**
 * Concatenates a byte sequence and a single byte.
 *
 * prefix: prefix
 * suffix: single-byte suffix
 *
 * Return value: concatenated CBytes.
 */
CBytes combine_bytes(CBytes prefix, unsigned char suffix);

#endif /* SAMPLE_H */
```

**单元名**：`sample`（从 `sample.h` 或 `SAMPLE_H` 提取）。Pascal 单元名是 `sample_abi_service_unit`——**合法**。

### 12.2 全部被跳过或损坏

```c
/* bad.h */

/* 函数定义 —— 跳过 */
int helper(void) { return 42; }

/* 布尔返回 —— 跳过 */
_Bool is_even(int x);

/* struct 参数 —— 跳过 */
double dist(struct Point p1, struct Point p2);

/* enum 参数 —— 跳过 */
int set_color(enum Color c);

/* wchar_t —— 跳过 */
int print_wide(wchar_t * s);

/* 函数指针参数 —— 跳过 */
void set_callback(void (*cb)(int));

/* 可变参数 —— 跳过 */
int printf_like(const char * fmt, ...);

/* union 参数 —— 跳过 */
void set_value(union Value v);

/* 非 char 指针 —— 跳过 */
void * allocate(int size);
void   use_ptr(int * p);

/* 非字节数组 —— 整条声明通过 Fill_C，但数组语义在生成层丢失 */
void fill_buffer(int buf[], int len);

/* 多维数组 —— 跳过 */
void matrix(int m[][10], int rows);

/* 全局变量 —— 跳过 */
int global_counter;

/* 初始化变量 —— 跳过 */
int initialized = 42;

/* struct 定义 —— 跳过 */
struct Foo { int x; int y; };

/* 无文件名、无 guard —— 单元名退化为 untitled.h */
/* 生成的 Pascal 代码里会有 unit untitled.h; —— 编译失败 */
```

### 12.3 未提供合法单元名的情况

```c
/* 1.0.3.h */            /* 文件名以数字开头，不是合法标识符 */
#ifndef 1_0_3_H         /* 宏名不是合法标识符 */
#define MAX_SIZE 1024    /* MAX_SIZE 不是 guard（无 _H 后缀） */

int add(int a, int b);
```

单元名退化为 `untitled.h`。生成 Pascal 代码时，`unit untitled.h;` **编译失败**。

**修复**：在头文件第一行加合法 guard：

```c
/* myunit.h */          /* 合法文件名 */
#ifndef MYUNIT_H        /* 合法 guard */
#define MYUNIT_H

int add(int a, int b);

#endif /* MYUNIT_H */
```

单元名变成 `myunit`——合法。

---

## 13. 自检清单

```c
// 1. 是函数原型（以 ; 结尾）吗？不是定义（无 { ... }）？
// 2. 是顶层吗？不在函数体 / struct / union / enum / typedef 内？
// 3. 无函数指针参数？
// 4. 无可变参数（...）？
// 5. 无多维数组？
// 6. 每个类型都在白名单里？
// 7. 指针只出现在 char * 家族中？
// 8. 数组只出现在 unsigned char [] 中？
// 9. 注释紧贴声明，或上方只隔空行？
// 10. 每个参数描述是否位于行首？
// 11. 多行描述续行是否缩进更深？
// 12. 第一段注释是否在前 200 字符内包含核心信息？
// 13. 头文件有合法文件名或 include guard（避免 untitled.h）？
```

| # | 检查项 | 失败时如何处理 |
|:-:|--------|----------------|
| 1 | 函数原型？ | 去掉函数体 |
| 2 | 顶层？ | 移到顶层 |
| 3 | 无函数指针？ | 用 `uint64_t` 承载句柄 |
| 4 | 无可变参数？ | 固定参数或 `CBytes` |
| 5 | 无多维数组？ | 展开为 `CBytes` |
| 6 | 类型在白名单？ | 改用整型 / 浮点 / `char *` / `CBytes` |
| 7 | 指针只在 `char *` 家族？ | 改用 `char *` 或 `uint64_t` 或 `CBytes` |
| 8 | 数组只在 `unsigned char []`？ | 改用 `unsigned char []` 或 `CBytes` |
| 9 | 注释在上方？ | 把注释移到上方 |
| 10 | 参数名在行首？ | 把名字移到行首 |
| 11 | 续行缩进更深？ | 加大缩进 |
| 12 | 第一段简短？ | 精简第一段 |
| 13 | 单元名合法？ | 加 `foo.h` + `FOO_H` guard |

---

## 14. 最小模板

### 14.1 标量签名模板

```c
/* my_unit.h */
#ifndef MY_UNIT_H
#define MY_UNIT_H

/**
 * <One sentence describing the function.>
 *
 * a: <description of a>
 * b: <description of b>
 *
 * Return value: <what is returned>.
 */
int my_func(int a, const char * b);

#endif /* MY_UNIT_H */
```

### 14.2 `CBytes` 签名模板

```c
/* my_bytes_unit.h */
#ifndef MY_BYTES_UNIT_H
#define MY_BYTES_UNIT_H

/**
 * <One sentence describing the function.>
 *
 * data: <description of the byte sequence>
 *
 * Return value: <description of the returned byte sequence>.
 */
CBytes transform_bytes(CBytes data);

#endif /* MY_BYTES_UNIT_H */
```

**应当做**：

- 用 `/** ... */` 写注释。
- 把参数描述放在一个块里，**参数名从行首开始**。
- 返回类型写在签名里。
- 续行比参数名缩进更深。
- 用 `CBytes` 承载二进制负载。
- 用 `char *` 承载字符串。
- **头文件必须有合法文件名或 include guard**（避免 `untitled.h`）。

**不应当做**：

- 使用函数指针参数、可变参数、多维数组。
- 使用 `bool`、`wchar_t`、struct、union、enum、非 char 指针、非字节数组。
- 依赖 `@return` 提供返回类型（虽然 C 里本就要求签名有返回类型）。
- 在头文件第一行/guard 里写非法标识符。
- 在 `char *` 返回类型上写 `const`（避免双重 `const`）。
- 把 `int buf[]` 当成数组——它在生成层会变成单个标量参数。

---

## 15. 快速查表

| 症状 | 原因 | 修复方式 |
|------|------|----------|
| 声明从 JSON 中消失 | 不是函数原型（有函数体） | 去掉 `{ ... }` |
| 声明从 JSON 中消失 | struct / enum / union / bool / wchar_t | 换成整型 / 浮点 / `char *` / `CBytes` |
| 声明从 JSON 中消失 | 函数指针参数 | 用 `uint64_t` 承载句柄 |
| 声明从 JSON 中消失 | 可变参数 `...` | 固定参数或 `CBytes` |
| 声明从 JSON 中消失 | **非 char 指针** | **用 `uint64_t` 承载地址，或 `CBytes`** |
| 声明从 JSON 中消失 | **多维数组** | **用 `CBytes`** |
| **数组参数变成了单个标量** | **`int buf[]` 数组语义在生成层丢失** | **改用 `unsigned char []` 或 `CBytes`** |
| 参数描述缺失 | 没有 `@param` / `name:` 行 | 加参数描述行 |
| 参数描述缺失 | 参数没有名字（`void f(int)`） | 给每个参数命名 |
| 工具描述为空 | 注释只有 `@param` / `@return` | 加一段自由文本 |
| 工具描述被截断 | 第一段超过 200 字符 | 精简第一段 |
| 行尾注释被忽略 | 注释在声明之后 | 移到声明上方 |
| **生成的 Pascal 单元名是 `untitled.h`** | **头文件缺合法文件名和 guard** | **加 `foo.h` + `FOO_H`** |
| **生成的 C 代码有 `const const`** | **返回类型写了 `const`** | **去掉返回类型的 `const`** |
| 重名函数被自动重命名 | 工具链自动去重 | 正常行为（`foo` → `foo1`） |
| JSON 往返后源码位置丢失 | 序列化不包含位置信息 | 正常行为 |

---

## 16. 设计原则

这些规则不是随意定的，背后有清晰的语义约束：

1. **仅函数原型**。ABI 工具链只关心跨语言可调用的函数。类型定义、变量、宏属于编译期概念，没有运行时意义。

2. **仅可序列化类型**。ABI 层需要在不同语言间序列化数据。能序列化的只有：整数、浮点、字符串、字节序列。其它类型在不同语言中表示不一致，无法保证正确传输。

3. **`char *` 是字符串的唯一可靠表示**。C 的字符串指针在语义上明确（以 `\0` 结尾），跨语言可序列化为字符串。其他指针（`int *`、`void *`）是进程内地址，跨进程无意义。

4. **`CBytes` 是字节序列的一等公民**。跨语言的二进制负载统一用字节序列表达。`unsigned char []` 与 `CBytes` 等价识别；其他数组类型（`int []` 等）无法保证元素的跨语言表示一致，会被降级为标量。

5. **函数指针和可变参数无法序列化**。函数指针是代码地址，可变参数个数不定。两者都无法用统一的数据格式表达。

6. **结构化注释**。注释是 AI 理解声明的唯一途径。规则（行首、缩进）都是为了让注释能被可靠解析，而不是让用户为难。

7. **单元名必须合法**。生成的 Pascal 代码需要合法单元名。`untitled.h` 是 fallback，不是预期结果。**写头文件时必须提供合法文件名或 include guard**。

8. **静默跳过**。工具链的设计哲学是"能解析就解析，不能解析就跳过"——不会因为一条声明不合法就让整个头文件失败。但这也意味着错误容易被忽视，所以需要这份文档把规则说清楚。

9. **第一段是工具描述**。AI 拿到的工具描述是单行、200 字符内的文本。把核心信息放在第一段，是对 AI 读者的尊重。

10. **数组语义不可靠是已知限制**。C 的 `int buf[]` 在工具链里会变成标量 `int`。这不是 bug，是"只有字节数组能跨语言序列化"这一约束的直接后果。**写数组参数时必须用 `unsigned char []` 或 `CBytes`**。

---

## 17. 修订记录

- **v10.0** —— 基于 ABI 生成器行为重建。新增 `CBytes` / `cbytes` 二进制负载支持。补充完整的跨语言类型映射表。明确 `char *` 家族是唯一可靠的指针类型、`unsigned char []` / `CBytes` 是唯一可靠的数组类型、`int buf[]` 数组语义会丢失。明确函数指针和可变参数必须拒绝。明确单元名提取规则和 `untitled.h` 问题的严重性。补充 `const` 返回类型的双重 `const` 陷阱。中文全文重写，面向编写者而非源码读者。
- **v9.0** —— 精简版。示例优先。
- **v8.0** —— 加入数组后缀处理规则。
- **v7.0** —— 加入单元名提取规则、工具描述拼接规则。
- **v6.0** —— 加入返回值注释指引。
- **v5.0** —— 加入多行注释规范化规则。
- **v4.0** —— 白名单与空行规则。

**本文档是编写契约。按本文写，声明就能被正确提取、归一化、生成；不按本文写，声明会被静默跳过，或者生成的代码不符合预期。**