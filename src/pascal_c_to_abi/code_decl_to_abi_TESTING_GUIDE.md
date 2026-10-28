# code_decl_to_abi — 各语言测试方法指南

> **文档定位**: 本文件说明 `code_decl_to_abi` 生成的测试程序在 17 种目标语言中如何准备环境、启动、运行与验证。
>
> **前置阅读**: `code_decl_to_abi_USER_GUIDE.md`（尤其是 Part II — 使用生成的代码）。
>
> **核心原则**: 所有语言的测试都遵循相同的两进程模型 —— **先启动 service，再启动 call**；都向 stdout 输出 `[PASS]` / `[FAIL]` / `[SKIP]` 行；都以 **exit code 0 表示成功、2 表示有失败**（部分语言用 1 表示致命错误）。
>
> **文档语言**: 中文。
>
> **生成代码语言**: 英文。

---

## 目录

1. [通用测试约定](#1-通用测试约定)
2. [测试产物的命名规律](#2-测试产物的命名规律)
3. [各语言测试方法](#3-各语言测试方法)
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
4. [跨语言测试](#4-跨语言测试)
5. [测试失败的排查步骤](#5-测试失败的排查步骤)

---

## 1. 通用测试约定

### 1.1 两进程模型

所有语言一致：

```
┌─────────────────────────────┐        ┌─────────────────────────────┐
│  终端 1 — Service            │        │  终端 2 — Call               │
│  监听 ipc:<Unit>_abi         │◄──────►│  连接 ipc:<Unit>_abi         │
│  P2P 组: <Unit>_service_test_p2p    │        │  一次调用所有 API × 所有变体  │
└─────────────────────────────┘        └─────────────────────────────┘
```

**启动顺序严格**：先 service，后 call。若先启动 call，它会等待 target 服务上线（各语言等待时间不同，通常 10–30 秒），超时即 FAIL。

### 1.2 端点与 P2P 命名

| 项 | 值 |
|----|-----|
| IPC 端点 | `ipc:<UnitName>_abi` |
| App 名称 | `<UnitName>_abi` |
| P2P 组名 | `<UnitName>_service_test_p2p` |
| Client 应用名 | `LF_TEST_CLIENT_SELF` |
| 辅助 API | `LF_TEST_WHOAMI`, `LF_TEST_ASK_SERVICE_CALL_ME`, `LF_TEST_REPORT_SERVICE_IDENTITY` |

这些名字由生成器统一注入，跨语言一致，因此**任何语言的 service 都能被任何语言的 call 测试**。

### 1.3 每个 API 的测试变体

对每个 routine，call 测试会依次尝试：

| 变体 | 说明 |
|------|------|
| `(app call)` | 按 App 名称同步调用 |
| `(app async)` | 按 App 名称异步调用 |
| `(app asyncSeq)` / `(app seq ...)` | 按 App 名称异步顺序调用 |
| `(uid call)` | 按 UID 同步调用（需先取得 service 的 UID） |
| `(uid async)` | 按 UID 异步调用 |
| `(uid asyncSeq)` | 按 UID 异步顺序调用 |
| `(p2pname call)` | 按 P2P 组名同步调用 |
| `(p2pname async)` | 按 P2P 组名异步调用 |
| `(p2pname asyncSeq)` | 按 P2P 组名异步顺序调用 |

Procedure 类型的 routine 只有 `notify` 系列变体。

### 1.4 输出与退出码

| 输出 | 含义 |
|------|------|
| `[PASS] <label>` 或 `[PASS] <label> = <value>` | 该变体通过 |
| `[FAIL] <label> -- <reason>` | 该变体失败 |
| `[SKIP] <label> -- <reason>` | 该变体被跳过（通常是 `no service UID`） |
| `[READY]` / `[OK] Service ready` | service 已就绪 |
| `[INFO]` | 诊断信息 |
| `[FATAL]` | 致命错误，程序退出 |

| 退出码 | 含义 |
|:------:|------|
| `0` | 全部 PASS 或 SKIP |
| `2` | 至少一个 FAIL |
| `1` | 环境准备失败（缺依赖、缺运行时、prepare 失败等） |
| 其他 | 语言运行时或编译错误 |

### 1.5 环境准备脚本

除 Pascal（由 test unit 自带）和 Python（模块自带 `__main__`）外，其他语言都附带一个 `setup_*_tests.ps1` 环境初始化脚本。**先跑脚本，再跑测试**。

脚本统一支持 `-Help`，会打印该语言的完整用法、前置依赖、失败退出码。

---

## 2. 测试产物的命名规律

| 语言 | Service 测试文件 | Call 测试文件 | 环境脚本 |
|------|------------------|---------------|----------|
| Pascal | `<Unit>_abi_service_test_unit.pas` | `<Unit>_abi_call_test_unit.pas` | — |
| Python | `<Unit>_abi_service_test.py` | `<Unit>_abi_call_test.py` | — |
| C++ | `<Unit>_abi_service_main.cpp` | `<Unit>_abi_call_main.cpp` | —（由 CMakeLists.txt 驱动） |
| C# | `<Unit>_abi_service_test___.cs` | `<Unit>_abi_call_test___.cs` | — |
| Rust | `<Unit>_abi_service_test.rs` | `<Unit>_abi_call_test.rs` | `setup_rust_tests.ps1` |
| Go | `<Unit>_abi_service_test.go` | `<Unit>_abi_call_test.go` | `setup_go_tests.ps1` |
| Java | `<Unit>AbiServiceMain.java` | `<Unit>AbiCallTestMain.java` | `setup_java_tests.ps1` + `run_java_service.ps1` / `run_java_call.ps1` |
| Node.js | `<Unit>_abi_service_test.js` | `<Unit>_abi_call_test.js` | `setup_node_tests.ps1` |
| TypeScript | `<Unit>_abi_service_test.ts` | `<Unit>_abi_call_test.ts` | `setup_ts_tests.ps1` |
| Erlang | `<Unit>_abi_service_main.erl` | `<Unit>_abi_call_main.erl` | `setup_erlang_tests.ps1` |
| Julia | `<Unit>_abi_service_test.jl` | `<Unit>_abi_call_test.jl` | `setup_julia_tests.ps1` + `run_julia_service.ps1` / `run_julia_call.ps1` |
| Zig | `<Unit>_abi_service_test.zig` | `<Unit>_abi_call_test.zig` | `setup_zig_tests.ps1` |
| Swift | `<Unit>_abi_service_test.swift` | `<Unit>_abi_call_test.swift` | `setup_swift_tests.ps1` |
| Ruby | `<Unit>_abi_service_test.rb` | `<Unit>_abi_call_test.rb` | `setup_ruby_tests.ps1` |
| Fortran | `<Unit>_abi_service_test.f90` | `<Unit>_abi_call_test.f90` | `setup_fortran_tests.ps1` |
| Dart | `<Unit>_abi_service_test.dart` | `<Unit>_abi_call_test.dart` | `setup_dart_tests.ps1` |
| R | `<Unit>_abi_service_test.R` | `<Unit>_abi_call_test.R` | `setup_R_tests.ps1` |

---

## 3. 各语言测试方法

### 3.1 Pascal

**测试产物**

- `<Unit>_abi_service_test_unit.pas`
- `<Unit>_abi_call_test_unit.pas`

**准备**

无环境初始化脚本。需要一个主程序把 test unit 挂起来。最小主程序：

```pascal
program pascal_abi_test;
{$mode delphi}{$H+}
uses
  SysUtils,
  <Unit>_abi_service_test_unit,   // service 侧
  <Unit>_abi_call_test_unit;      // call 侧
begin
  if ParamStr(1) = 'service' then
    Start_Service_Test
  else
    Run_Call_Test;
end;
```

或直接编写一个 `Run_Call_Test` 的独立主程序。

**编译**

```bash
fpc -Fu<dir-with-lingofuse_import.pas> -Fu<dir-with-Z.Core.pas> \
    -Fu<dir-with-lingofuse_helper.pas> pascal_abi_test.pas
```

**运行**

终端 1：
```bash
./pascal_abi_test service
```
等待 `[OK] service ready`，按 Enter 停止。

终端 2：
```bash
./pascal_abi_test call
```

**预期输出**

- 每个 API × 每个变体一行 `[PASS]` / `[FAIL]` / `[SKIP]`
- 末尾 `=== Summary ===`，列出 Pass / Fail / Skip
- 失败时退出码为 2

**注意**

- `Run_Call_Test` 内部的 `Test_<Api>` 会先尝试 `app call`，然后依次尝试 async、uid、p2pname 变体。`service UID` 通过 `LF_TEST_WHOAMI` 与 `LF_TEST_ASK_SERVICE_CALL_ME` 的协作取得，若这两个 API 在 service 侧未注册，UID 相关变体全部 SKIP。
- Pascal 侧的 service test unit 提供 `Start_Service_Test` / `Stop_Service_Test` / `Is_Service_Test_Running`，可嵌入到已有的 Pascal 应用里。

---

### 3.2 Python

**测试产物**

- `<Unit>_abi_service_test.py`
- `<Unit>_abi_call_test.py`

**准备**

```bash
pip install py-lingofuse
```

或（使用 v3 工具链的 `lingofuse/` 源码目录）：

```bash
# PowerShell
$env:PYTHONPATH = "<v3>/src"
```

**运行**

终端 1：
```bash
python <Unit>_abi_service_test.py
```
等待 `[OK] Service ready`，按 Enter 或 Ctrl+C 停止。

终端 2：
```bash
python <Unit>_abi_call_test.py
```

**预期输出**

与 Pascal 一致。Python 版本额外有一行 `[INFO] total tests scheduled: N`。

**注意**

- Python test 会尝试使用 `asyncio.run(...)` 调用 async 变体，需 Python 3.7+。
- UID 相关变体需要 service 侧成功响应 `LF_TEST_ASK_SERVICE_CALL_ME`（反向调用 client），若 service 侧没注册这个 API，UID 变体会 SKIP。
- service test 默认监听 `ipc:<Unit>_abi`。

---

### 3.3 C++

**测试产物**

- `<Unit>_abi_service_main.cpp`
- `<Unit>_abi_call_main.cpp`
- `CMakeLists.txt`

**准备**

需要 `LingoFuse.h`、`LingoFuse.c`、`LingoFuse.hpp`、`lf_io.hpp` 所在的目录。

**构建**

```bash
cmake -S . -B build -DLINGOFUSE_CPP_DIR=<dir-with-LingoFuse.h>
cmake --build build --config Release
```

或用原始 `g++`：

```bash
g++ -std=c++17 -I<dir-with-LingoFuse.hpp> \
    <Unit>_abi_service.cpp <Unit>_abi_service_main.cpp \
    LingoFuse.c -o service_test -pthread
```

**运行**

终端 1：
```bash
./build/<Unit>_abi_service_test
```
等待 `[OK] Service ready`，按 Enter 停止。

终端 2：
```bash
./build/<Unit>_abi_call_test
```

**注意**

- C++ test 程序开头会调用 `LF_LoadLibrary()`；若失败，会打印 `[FATAL] LF_LoadLibrary failed.` 并退出。此时需把 `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib` 放到可执行文件同目录，或放到 OS loader search path。
- MSVC 用户必须加 `/utf-8`，否则描述字符串会以系统 codepage 编码，与 UTF-8 不一致。
- C++ 侧支持 async 变体（`*_Async`、`*_AsyncSequenced`）以及 UID / P2PName 的所有 9 种组合。

---

### 3.4 C#

**测试产物**

- `<Unit>_abi_service_test___.cs`
- `<Unit>_abi_call_test___.cs`

**准备**

两个测试程序都需要一个独立的 `.NET console project`（不能和库文件混在一个项目里，否则触发 `CS0017: Program has more than one entry point`）。

```bash
# service 侧
dotnet new console -o service_test
cd service_test
cp ../<Unit>_abi_service.cs .
cp ../<Unit>_abi_service_test___.cs Program.cs
cp ../LingoFuse64.dll .
dotnet run
```

**运行**

终端 1：
```bash
cd service_test
dotnet run
```

终端 2：
```bash
cd call_test     # 同样方式建立
dotnet run
```

**注意**

- C# test 使用 `DllImportResolver` 自动定位 `LingoFuse64.dll` / `lingofuse64.dll`（Windows 64-bit）等运行时，因此把 DLL 放到 `dotnet run` 的工作目录即可。
- `ABI.Timeout` 默认 5000 ms，可通过修改 `Program.cs` 里的 `ABI.Timeout = 30000;` 调整。
- `ABI.TargetApp` 默认 `<Unit>_abi`，如需跨机器或跨进程需同步两端。

---

### 3.5 Rust

**测试产物**

- `<Unit>_abi_service_test.rs`
- `<Unit>_abi_call_test.rs`
- `setup_rust_tests.ps1`
- `Cargo.toml`（由 setup 脚本创建）

**准备**

```powershell
.\setup_rust_tests.ps1 -LingofuseDir <dir-with-lingofuse-crate> -RunSmoke
```

脚本会：

1. 把 `.rs` 文件拷进 `src/` 与 `examples/`；
2. 创建 `Cargo.toml` 并注入 `lingofuse = { path = "<LingofuseDir>" }`；
3. 扫描并清理陈旧 copy；
4. `cargo build`（`-RunSmoke` 时额外 `cargo build --examples`）。

**运行**

终端 1：
```bash
cargo run --example service_test
```
等待 `[OK] Service ready`，按 Enter 停止。

终端 2：
```bash
cargo run --example call_test
```

**注意**

- Rust test 使用 `std::sync::mpsc` 与 `catch_unwind` 保护 async 回调，任何 panic 都会被捕获并转为 `[FAIL]`。
- `setup_rust_tests.ps1` 有 `-Force` 参数强制覆盖旧文件；有 `-RunSmoke` 参数编译 examples；`-Help` 显示完整用法。
- 若 `cargo build` 报 `lingofuse` crate 找不到，检查 `Cargo.toml` 中的 `path` 是否指向包含 `Cargo.toml` 与 `src/lib.rs` 的目录。

---

### 3.6 Go

**测试产物**

- `<Unit>_abi_service_test.go`
- `<Unit>_abi_call_test.go`
- `setup_go_tests.ps1`
- `go.mod` / `go.sum`（由 setup 脚本生成）

**准备**

```powershell
.\setup_go_tests.ps1 -LingoFuseGo <dir-with-lingofuse-go-module> -Force
```

脚本会：

1. 把库文件（`<Unit>_abi_call.go` / `<Unit>_abi_service.go`）与两个 test 主程序整理到 `.go_clean_build/`；
2. 把 test 程序分别放到 `<Unit>_abi_service_test/main.go` 与 `<Unit>_abi_call_test/main.go`；
3. 生成 `go.mod` 并注入 `replace github.com/PassByYou888/LingoFuse/go => <path>`；
4. 执行 `go mod tidy`、`gofmt`、`go build ./...`、`go vet ./...`。

**运行**

终端 1：
```bash
cd .go_clean_build
go run ./<Unit>_abi_service_test
```

终端 2：
```bash
cd .go_clean_build
go run ./<Unit>_abi_call_test
```

**注意**

- Go 的 test 输出使用 `[PASS]` / `[FAIL]` / `[SKIP]` 前缀；`_g.pass` / `_g.fail` / `_g.skip` 三个计数器最后汇总。
- test 内部用 `chan callResult[T]` 与 `select` 等待 async 回调，超时 10 秒。
- 脚本参数 `-GOPROXY` 可指定 Go module 代理（默认 `https://goproxy.cn,direct`）；`-Clean` 在成功后删除 `.go_clean_build/`。
- 若报 `stale Go files detected`，说明生成的 `.go` 是旧版（含 Pascal 类型名），需重新生成。

---

### 3.7 Java

**测试产物**

- `<Unit>AbiServiceMain.java`
- `<Unit>AbiCallTestMain.java`
- `pom.xml`
- `setup_java_tests.ps1` + `run_java_service.ps1` / `run_java_call.ps1`

**准备**

```powershell
.\setup_java_tests.ps1 -LingoFuseJava <dir-with-lingofuse-java-project>
```

需要 JDK 22+ 与 Maven 3.9+。脚本会：

1. 校验 `LingoFuseJava` 目录与 `lingofuse*.jar`（缺失时自动 `mvn -Dmaven.test.skip=true package`）；
2. 拷贝 `pom.xml`、`lingofuse.jar`、四个 `.java` 文件到 `.java_clean_build/`；
3. 拷贝 `LingoFuse64.dll` / `lingofuse.so` / `lingofuse.dylib`；
4. `mvn -q -DskipTests compile`。

**运行**

终端 1：
```powershell
.\run_java_service.ps1
```

终端 2：
```powershell
.\run_java_call.ps1
```

也可以手动：

```bash
cd .java_clean_build
mvn -q -DskipTests compile exec:java -Dexec.mainClass="lingofuse.abi.<lower_unit>.<Unit>AbiServiceMain"
```

**注意**

- Java 的 service test 监听 `ipc:<Unit>_abi`，`kTargetApp`、`kTargetP2P`、`kEndpoint` 三个常量在 `main` 方法开头注入。
- 测试使用 `CountDownLatch` + `AtomicReference` 等待 async 回调，超时 5000 ms。
- `libraryLoader.selectPlatformFileName()` 自动选择平台文件名，若失败会报 `[FATAL] LingoFuse native library not found`。
- `setup_java_tests.ps1` 有 `-Force` / `-Clean` / `-Help`；`-Clean` 在成功后删除 `.java_clean_build/`。

---

### 3.8 Node.js

**测试产物**

- `<Unit>_abi_service_test.js`
- `<Unit>_abi_call_test.js`
- `setup_node_tests.ps1`
- `package.json`（由 setup 脚本生成）

**准备**

```powershell
.\setup_node_tests.ps1 -LingoFuseJs <dir-with-lingofuse-js> -RunSmoke
```

脚本会：

1. 检查 `LingoFuseJs/node_modules/koffi`（缺失时自动 `npm install`）；
2. 写 `package.json`，`lingofuse-js` 指向 `LingoFuseJs`；
3. `npm install`；
4. `node --check` 语法检查四个 `.js` 文件；
5. `-RunSmoke` 时后台启动 service 测试，前台跑 call 测试并验证退出码。

**运行**

终端 1：
```bash
node <Unit>_abi_service_test.js
```
等待 `[OK] service ready`。

终端 2：
```bash
node <Unit>_abi_call_test.js
```

**注意**

- Node.js test 使用 `process.on('SIGINT')` 捕获 Ctrl+C 做优雅关闭。
- `_race(promise, timeoutMs, label)` 包裹每个 async 调用，超时即 `[FAIL]`。
- service 侧注册了三个辅助 API（`LF_TEST_WHOAMI`、`LF_TEST_ASK_SERVICE_CALL_ME`、`LF_TEST_REPORT_SERVICE_IDENTITY`）用于 UID 探测与反向调用。
- 若 `npm install` 失败，`setup_node_tests.ps1` 会打印完整错误并退出 1。

---

### 3.9 TypeScript

**测试产物**

- `<Unit>_abi_service_test.ts`
- `<Unit>_abi_call_test.ts`
- `setup_ts_tests.ps1`
- `tsconfig.json` / `package.json`（由 setup 脚本生成）

**准备**

```powershell
.\setup_ts_tests.ps1 -LingoFuseTs <dir-with-lingofuse-ts> -RunSmoke
```

脚本会：

1. 校验 `LingoFuseTs/package.json` 与 `dist/index.js`（必须先 `npm run build`）；
2. 写 `tsconfig.json`（`strict` / `esModuleInterop` / `module: commonjs`）与 `package.json`；
3. **自动建立 `node_modules/lingofuse-ts` junction**（Windows 用 `mklink /J` 或 symlink），指向 `LingoFuseTs`；
4. `npm install`；
5. `tsc --noEmit` 类型检查；
6. `-RunSmoke` 时后台启动 service，前台跑 call test。

**运行**

**默认（tsx 直跑）**：

终端 1：
```bash
node node_modules/tsx/dist/cli.mjs <Unit>_abi_service_test.ts
```

终端 2：
```bash
node node_modules/tsx/dist/cli.mjs <Unit>_abi_call_test.ts
```

**`-Compiled` 模式（tsc 预编译）**：

```powershell
.\setup_ts_tests.ps1 -LingoFuseTs <...> -Compiled
# 之后用 node dist/<Unit>_abi_service_test.js 运行
```

**注意**

- TypeScript 的 `reportIdentityCb` 必须注册在 `_koffi.register(...)` 中，`koffi` 是 `lingofuse-ts` 的内部绑定。
- 依赖 `LfCallFuncPtr` / `LfNotifyFuncPtr` 指针类型，由 `lingofuse-ts` 导出。
- 若 `LingoFuseTs` 路径含有中文或空格，建议使用 `-SkipAutoLink` 并手工建立 junction。

---

### 3.10 Erlang

**测试产物**

- `<Unit>_abi_service_main.erl`
- `<Unit>_abi_call_main.erl`
- `setup_erlang_tests.ps1`
- `rebar.config` / `<Unit>_abi.app.src`（由 setup 脚本生成）

**准备**

需要 **OTP 27+**（`erl`、`erlc`、`escript` 都在 PATH 中）。

```powershell
.\setup_erlang_tests.ps1 -LingofuseEbin <dir-with-lingofuse.beam> -RunSmoke
```

脚本会：

1. 校验 `lingofuse.beam`（自动搜索 `<dir>` / `<dir>/lingofuse/ebin` / `<dir>/_build/default/lib/lingofuse/ebin` / `<dir>/ebin`）；
2. 校验 OTP ≥ 27；
3. 把 `.erl` 文件整理到 `src/`；
4. 生成 `rebar.config` 与 `.app.src`；
5. 用 `rebar3`（优先）或 `erlc`（回退）编译；
6. `-RunSmoke` 时启动 service 测试、跑 call 测试、检查退出码。

**运行**

终端 1：
```bash
erl -noshell -pa <lingofuse-ebin> -pa _build/default/lib/<Unit>_abi/ebin \
    -eval "<Unit>_abi_service_main:main([])."
```
等待 `[OK] service ready`。

终端 2：
```bash
erl -noshell -pa <lingofuse-ebin> -pa _build/default/lib/<Unit>_abi/ebin \
    -eval "<Unit>_abi_call_main:main([])."
```

**注意**

- 两个主程序都是 `-module('<Unit>_abi_service_main')` 形式，`main([])` 是入口。
- service 侧监听 `ipc:<Unit>_abi`，`main` 函数启动后 `timer:sleep(15000)` 再 `loop(App)`（允许 service 有 15 秒启动等待期）。
- call 侧在 `run_tests/1` 中用 `run_sync_test` / `run_async_test` / `run_uid_*` / `run_p2p_*` 封装每种变体；UID/P2P 路由超时归为 SKIP 而非 FAIL。
- 编译后若 `*.beam` 落在错误的 `ebin`，检查 `rebar3 compile` 是否成功，或用手工 `erlc -o ebin src/*.erl`。

---

### 3.11 Julia

**测试产物**

- `<Unit>_abi_service_test.jl`
- `<Unit>_abi_call_test.jl`
- `setup_julia_tests.ps1` + `run_julia_service.ps1` / `run_julia_call.ps1`
- `Project.toml` / `runtests.jl`（由 setup 脚本生成）

**准备**

需要 **Julia 1.9+**，并开启至少 2 个线程（测试会检查 `Threads.nthreads() < 2` 并报错）。

```powershell
.\setup_julia_tests.ps1 -LingoFuseJulia <dir-with-lingofuse-julia-package>
```

脚本会：

1. 校验 `Project.toml` 与 `src/LingoFuse.jl`；
2. 把四个 `.jl` 文件与 `Project.toml` / `runtests.jl` 拷进 `.julia_clean_build/`；
3. 拷贝 `LingoFuse64.dll` / `liblingofuse.so` / `liblingofuse.dylib`；
4. `Pkg.develop(path="<LingoFuseJulia>")` 安装依赖。

**运行**

终端 1：
```powershell
.\run_julia_service.ps1
```
等价于 `julia --project=. --threads=2 <Unit>_abi_service_test.jl --serve-only`。

终端 2：
```powershell
.\run_julia_call.ps1
```

**注意**

- **必须 `--threads=2`**，否则脚本立即报错退出。
- `--serve-only` 模式只跑 service、不跑 self-loop 测试；跨进程测试配合 `run_julia_call.ps1` 使用。
- 若 `loader.jl` 找不到运行时库，可设置环境变量 `LINGOFUSE_LIBRARY=<绝对路径到 .dll>`。
- `setup_julia_tests.ps1` 的 `-Clean` 会在成功后删除 `.julia_clean_build/`。

---

### 3.12 Zig

**测试产物**

- `<Unit>_abi_service_test.zig`
- `<Unit>_abi_call_test.zig`
- `setup_zig_tests.ps1`
- `build.zig` / `build.zig.zon`（由 setup 脚本生成）

**准备**

需要 **Zig 0.17+**。

```powershell
.\setup_zig_tests.ps1 -LingofuseDir <dir-with-lingofuse-zig>
```

脚本会：

1. 校验 `LingofuseDir/build.zig`、`build.zig.zon`、`src/lingofuse.zig`；
2. 把四个 `.zig` 文件拷进 `src/`；
3. 创建 `build.zig`（含 service_test / call_test 两个 executable）；
4. 创建 `build.zig.zon`（注入 `.lingofuse = .{ .path = "<relative>" }`）；
5. 清理 `.zig-cache` / `zig-out`；
6. `zig build`（若 fingerprint 错误自动 patch 并重试最多 3 次）；
7. 校验 `zig-out/bin/<Unit>_abi_service_test.exe` 与 `_call_test.exe` 存在；
8. `-RunSmoke` 时对两个可执行文件跑 `--help`。

**运行**

终端 1：
```bash
.\zig-out\bin\<Unit>_abi_service_test.exe
```
等待 `[OK] Service ready`。

终端 2：
```bash
.\zig-out\bin\<Unit>_abi_call_test.exe
```

**注意**

- Zig service test **120 秒自动退出**（`TEST_AUTO_EXIT_SECONDS`）。
- test 依赖 `extern "c" fn Sleep(ms: u32)` 与 `extern "c" fn GetTickCount64() u64`（Windows）。Linux/macOS 需自行适配。
- 若 `zig build` 报 `invalid fingerprint`，脚本会自动提取正确的 fingerprint 并写回 `build.zig.zon`，最多重试 3 次；3 次后仍失败会报错。
- 若 `LingofuseDir` 与 `GenDir` 不同盘，脚本会拒绝运行（`build.zig.zon` 只接受相对路径）。

---

### 3.13 Swift

**测试产物**

- `<Unit>_abi_service_test.swift`
- `<Unit>_abi_call_test.swift`
- `setup_swift_tests.ps1`
- `Package.swift`（由 setup 脚本生成）

**准备**

需要 **Swift 5.9+**（推荐 Xcode Command Line Tools 或 swift.org 官方工具链）。

```powershell
.\setup_swift_tests.ps1 -LingofuseDir <dir-with-lingofuse-swift-package>
```

脚本会：

1. 校验 `LingofuseDir/Package.swift` 与 `Sources/LingoFuse/`；
2. 把 test 文件重命名为 `Sources/ServiceTest/main.swift` 与 `Sources/CallTest/main.swift`；
3. 把 service / call 库放到 `Sources/<Unit>_abi_service/` 与 `Sources/<Unit>_abi_call/`；
4. 生成 `Package.swift`（含 `ServiceTest` / `CallTest` 两个 executable）；
5. 扫描 `.swift` 文件检查 Pascal 类型名（`Integer` / `Cardinal` / `int64` 等）；
6. `swift build`（`-RunSmoke` 时额外 `swift build --product ServiceTest --product CallTest`）。

**运行**

终端 1：
```bash
swift run ServiceTest
```
等待 `[OK] Service ready`，按 Enter 停止。

终端 2：
```bash
swift run CallTest
```

**注意**

- Swift 侧在 macOS `.v12` 平台上测试；Linux 需确认 `LingofuseDir` 的 `Package.swift` 兼容 Linux。
- 如果 `swift build` 报 stale Pascal 类型名，脚本会阻止构建并提示重新生成。
- `Package.swift` 中的 `.package(path: "<normalizedLingofuse>")` 由 setup 脚本注入；`LingofuseDir` 可用相对路径或绝对路径。

---

### 3.14 Ruby

**测试产物**

- `<Unit>_abi_service_test.rb`
- `<Unit>_abi_call_test.rb`
- `setup_ruby_tests.ps1`

**准备**

需要 **Ruby 3.0+**（RubyInstaller with DevKit 推荐）以及 `lingofuse` gem。

```powershell
.\setup_ruby_tests.ps1 -RubyLibDir <dir-with-lingofuse.rb>
```

注意 `-RubyLibDir` 是 **`lib/` 目录**，不是 binding 根目录。脚本会：

1. 校验 `lingofuse.rb` 与 `lingofuse/` 子目录；
2. 校验 `lingofuse_ext.so` / `lingofuse_ext.dll` / `lingofuse_ext.bundle` 存在（缺失时提示先跑 `setup_build_env.ps1`）；
3. 探测 `require 'lingofuse'` 与 `LingoFuse::NativeBridge.available?`；
4. `ruby -c` 语法检查四个 `.rb` 文件；
5. 扫描 stale Pascal 类型名；
6. `ruby -I <RubyLibDir> -I <GenDir> -e "require '<Unit>_abi_service'; require '<Unit>_abi_call'"` 冒烟加载。

**运行**

终端 1：
```bash
ruby -I <RubyLibDir> -I <GenDir> <Unit>_abi_service_test.rb
```
等待 `[OK] Service ready`，按 Enter 停止。

终端 2：
```bash
ruby -I <RubyLibDir> -I <GenDir> <Unit>_abi_call_test.rb
```

**注意**

- Ruby test 内部使用 `module_function` 定义的所有函数都挂在 `<Unit>_abi::Service` 与 `<Unit>_abi::Call` 模块下；test 程序末尾直接调用 `<Unit>_abi::CallTest.main`。
- UID 探测通过 `lf_uid_call` 与 `lf_p2pname_call` 完成；若 service 侧没注册 `LF_TEST_ASK_SERVICE_CALL_ME`，UID 变体会 SKIP。
- Ruby 的 service test 会等待 stdin 输入后关闭。

---

### 3.15 Fortran

**测试产物**

- `<Unit>_abi_service_test.f90`
- `<Unit>_abi_call_test.f90`
- `setup_fortran_tests.ps1`

**准备**

需要 **gfortran + gcc + g++** 在 PATH 中。

```powershell
.\setup_fortran_tests.ps1 -LingoFuseDir <dir-with-LingoFuse.h-and-lf_fortran_mod>
```

`LingoFuseDir` 必须包含：`LingoFuse.h`、`LingoFuse.c`、`lf_fortran.h`、`lf_fortran.cpp`、`lf_fortran_mod.f90`。脚本会：

1. 编译 `LingoFuse.c` → `LingoFuse.o`
2. 编译 `lf_fortran.cpp` → `lf_fortran.o`
3. 编译 `lf_fortran_mod.f90` → `lf_fortran_mod.o` + `.mod`
4. 编译四个生成的 `.f90` 文件
5. 链接 `.fortran_build/<Unit>_abi_service_test.exe` 与 `<Unit>_abi_call_test.exe`
6. 拷贝 `LingoFuse64.dll` / `z_ipc_64.dll` / `mimalloc64.dll`
7. `-RunSmoke` 时后台启动 service 测试、跑 call 测试

**运行**

终端 1：
```bash
cd .fortran_build
./<Unit>_abi_service_test.exe
```
等待 `[READY]` 输出。

终端 2：
```bash
cd .fortran_build
./<Unit>_abi_call_test.exe
```

**注意**

- Fortran service test 内部调用 `Sleep(ms)`（Windows API），有 30 秒默认超时；也可用 `--seconds=N` 与 `--sentinel=PATH` 参数覆盖。
- 停止 service 测试：按 Ctrl+C，或创建 sentinel 文件 `LingoFuse_FortranServiceTest.exit`。
- Fortran 使用 `-lstdc++ -static-libgcc -static-libstdc++` 静态链接，运行时只需 `LingoFuse64.dll` / `z_ipc_64.dll`。
- 若 `-LingoFuseDir` 给的是 binding 根目录，脚本会自动探测 `c_ext/` 或 `fortran/c_ext/` 子目录。

---

### 3.16 Dart

**测试产物**

- `<Unit>_abi_service_test.dart`
- `<Unit>_abi_call_test.dart`
- `setup_dart_tests.ps1`
- `pubspec.yaml`（由 setup 脚本生成）

**准备**

需要 **Dart 3.0+**。

```powershell
.\setup_dart_tests.ps1 -LingoFuseDart <dir-with-lingofuse-dart-package>
```

脚本会：

1. 校验 `LingoFuseDart/pubspec.yaml` 与 `lib/lingofuse.dart`；
2. 写 `pubspec.yaml`，`lingofuse` 依赖指向 `LingoFuseDart`；
3. `dart pub get`；
4. 拷贝 `lf_dart_bridge.dll`；
5. `dart analyze` 四个文件（`--no-fatal-warnings`）；
6. `-RunSmoke` 时后台启动 service 测试，前台跑 call 测试。

**运行**

终端 1：
```bash
dart run <Unit>_abi_service_test.dart
```
等待 `[OK] service ready`。

终端 2：
```bash
dart run <Unit>_abi_call_test.dart
```

**注意**

- Dart test 使用 `BridgeHost.start()` 启动 FFI 桥；`FrameBridge.instance.registerP2PCall(...)` 注册 P2P 变体。
- service 侧使用 `Future.delayed(Duration(...))` 与 `Completer` 实现 async 超时；超时 10 秒。
- 若 `dart analyze` 失败（exit ≥ 2），`setup_dart_tests.ps1` 会以 1 退出。
- `lf_dart_bridge.dll` 由 `LingoFuseDart` 提供；可用 `-LingoFuseBridge <path>` 显式指定（未在参数表中但源码支持）。

---

### 3.17 R

**测试产物**

- `<Unit>_abi_service_test.R`
- `<Unit>_abi_call_test.R`
- `setup_R_tests.ps1`

**准备**

需要 **R 4.x** 与 `lingofuse` R 包（版本 2.0+）。

```powershell
.\setup_R_tests.ps1 -RuntimeDir <dir-with-LingoFuse64.dll>
```

脚本会：

1. 校验 `LingoFuse64.dll`（自动探测 `Binary/`、`runtime/`、`..\Binary/` 等子目录）；
2. 校验 `Rscript.exe` 在 PATH；
3. 探测 `lingofuse` 包的 API surface（要求 `lf_load`、`lf_call_bin`、`lf_uid_call_bin`、`lf_p2pname_call_bin`、`lf_notify_bin`、`lf_uid_notify_bin`、`lf_p2pname_notify_bin`、`lf_register_call`、`lf_register_notify`、`lf_register_p2p_call`、`lf_register_p2p_notify`、`lf_poll`、`lf_run` 全部存在，且 `lf_register_call` 支持 `bin` 与 `with_context` 参数）；
4. 探测 `bit64`（可选，int64/uint64 必需）；
5. `-RunSmoke` 时后台启动 service 测试、跑 call 测试。

**运行**

终端 1：
```powershell
$env:LINGOFUSE_RUNTIME = "<RuntimeDir>"
$env:ABI_SERVICE_TIMEOUT = "30"
Rscript --vanilla <Unit>_abi_service_test.R
```
等待 `[READY]`。

终端 2：
```powershell
$env:LINGOFUSE_RUNTIME = "<RuntimeDir>"
Rscript --vanilla <Unit>_abi_call_test.R
```

**注意**

- R service test 使用 `lf_poll(50)` 轮询事件；`ABI_SERVICE_TIMEOUT`（秒）控制空闲超时，默认 30 秒。
- call test 使用 `run_test(label, fn)` 包裹每个变体；`run_test_skip_if_no_bit64` 在没有 `bit64` 时把 int64 相关变体标记为 SKIP。
- 若 `lingofuse` 包 API surface 不完整，setup 脚本会明确报出缺失函数并退出 1。
- R test 的 `get_script_dir()` 从 `commandArgs()` 的 `--file=` 参数解析，因此用 `Rscript --vanilla <path>` 启动是必需的。

---

## 4. 跨语言测试

ABI 线协议语言无关，任意两种语言的 service 与 call 可以互连。

### 4.1 步骤

1. 选择语言 A 作为 service，语言 B 作为 call；
2. 用**同一份源 unit** 分别生成两种语言的全部产物；
3. 按 A 的 `setup_*_tests.ps1 -Help` 准备环境，启动 A 的 **service test**；
4. 按 B 的 `setup_*_tests.ps1 -Help` 准备环境，启动 B 的 **call test**；
5. 观察 B 的 `[PASS]` / `[FAIL]` / `[SKIP]` 输出。

### 4.2 常见组合

| Service 语言 | Call 语言 | 备注 |
|--------------|-----------|------|
| Pascal | Python / C++ / C# / Rust / … | Pascal 作为参考实现，适合做对照 |
| C++ | Python / Go / Java | 性能对比场景 |
| Python | 任何语言 | 快速原型验证 |
| Rust | 任何语言 | 内存安全 + 高性能场景 |

### 4.3 关键点

- **两端必须用同一源 unit 生成**。不同源 unit 生成的 API 名、类型表可能不同。
- **UID / P2PName 变体需要 service 侧注册了 `LF_TEST_WHOAMI` 与 `LF_TEST_ASK_SERVICE_CALL_ME`**。跨语言时若 B 的 call test 触发这两个辅助 API 而 A 的 service 没注册，则 UID 变体会 SKIP（不算 FAIL）。
- **端点名 `<Unit>_abi` 全局唯一**：同时跑多组测试会互相干扰。建议每组测试前用 `ps aux | grep` 或任务管理器确认没有残留 service。

---

## 5. 测试失败的排查步骤

### 5.1 快速定位

1. **看 service 是否打印 `[OK] Service ready`**。若否，问题在 service 启动阶段；
2. **看 call 是否在 30 秒内连上 service**。若否，检查端点 `ipc:<Unit>_abi` 是否一致；
3. **看 `[FAIL]` 的 label 与 reason**。label 里带变体名（`app call` / `uid async` / …），reason 里通常是具体的异常消息。

### 5.2 按症状分类

| 症状 | 可能原因 | 修复 |
|------|----------|------|
| `[FATAL] LF_LoadLibrary failed` | 运行时库不在可执行文件同目录或 loader search path | 见 `code_decl_to_abi_USER_GUIDE.md` Chapter 13 |
| `[FATAL] createApp failed` | LingoFuse 运行时版本不匹配 | 用与 binding 匹配的运行时 |
| `[FATAL] prepareDone failed` | 端点名冲突，或 service 未启动 | 检查端点名；确认 service 在跑 |
| `[FAIL] <Api>(app call) -- nil response` | 目标 App 名不匹配，或超时过短 | 检查两端 `TargetApp`；加大 timeout |
| `[FAIL] <Api>(app call) -- input truncated` | 两端字段数不一致 | 确认两端由同一模型生成 |
| `[FAIL] <Api>(uid call)` 且频繁出现 | service 侧没注册 `LF_TEST_ASK_SERVICE_CALL_ME` | service 侧补上该辅助 API |
| 全部 `[SKIP]` | service 侧 `LF_TEST_WHOAMI` 没注册 | service 侧补上该辅助 API |
| 单语言 PASS，跨语言 FAIL | 两端类型表不一致 | 检查两端 `ABI_Type_To_<Lang>_Decl` |
| `[FAIL] <Api>(app async) -- timeout` | async 回调内调用了 `LF_Call` 导致死锁 | 把回调内调用投递到独立线程 |

### 5.3 收集诊断信息

- **service 侧日志**：`setup_*_tests.ps1 -RunSmoke` 会把 service stdout/stderr 存到 `smoke_service.out.log` / `smoke_service.err.log`（各语言文件名可能略有不同）。
- **call 侧日志**：直接看终端输出，或重定向到文件。
- **运行时日志**：设置环境变量 `LF_LOG=1`（若 binding 支持）可开启 LingoFuse 内部日志。

### 5.4 复现最小用例

如果某个 API 失败，尝试：

1. **只跑该 API 的 `app call` 变体**（临时改 call test 的 `test_<Api>` 函数，去掉 uid / p2pname 变体）；
2. **只跑该 API 的 `app notify` 变体**（若是 procedure）；
3. **看 service 侧 `<Api>` 的 `internal_call_<Api>` 桩体**是否还是 `TODO` / 返回 0。

### 5.5 终极调试

- 用 Wireshark 或 LingoFuse 内置的日志功能抓取实际字节流，与 `code_decl_to_abi_USER_GUIDE.md` Chapter 16 的线协议描述逐字节对照。
- 若怀疑是运行时问题，用 C++ 或 Pascal 的极简测试程序单独验证 `LF_Call` / `LF_Notify` 是否正常。

---

## 附录 A — 每种语言的环境脚本速查

| 语言 | 脚本 | 必填参数 | 常用可选参数 |
|------|------|----------|--------------|
| Rust | `setup_rust_tests.ps1` | `-LingofuseDir` | `-Force`、`-RunSmoke` |
| Go | `setup_go_tests.ps1` | `-LingoFuseGo` | `-Force`、`-Clean`、`-GOPROXY` |
| Java | `setup_java_tests.ps1` | `-LingoFuseJava` 或 `-LingoFuseJar` | `-LingoFuseLib`、`-Force`、`-Clean` |
| Node.js | `setup_node_tests.ps1` | `-LingoFuseJs` | `-Force`、`-RunSmoke` |
| TypeScript | `setup_ts_tests.ps1` | `-LingoFuseTs` | `-Force`、`-RunSmoke`、`-Compiled`、`-SkipInstall`、`-SkipAutoLink` |
| Erlang | `setup_erlang_tests.ps1` | `-LingofuseEbin` | `-Force`、`-Clean`、`-RunSmoke` |
| Julia | `setup_julia_tests.ps1` | `-LingoFuseJulia` | `-LingoFuseLib`、`-Force`、`-Clean` |
| Zig | `setup_zig_tests.ps1` | `-LingofuseDir` | `-Force`、`-RunSmoke` |
| Swift | `setup_swift_tests.ps1` | `-LingofuseDir` | `-Force`、`-RunSmoke` |
| Ruby | `setup_ruby_tests.ps1` | `-RubyLibDir` | （仅 `-Help`，无环境参数） |
| Fortran | `setup_fortran_tests.ps1` | `-LingoFuseDir` | `-Force`、`-Clean`、`-RunSmoke` |
| Dart | `setup_dart_tests.ps1` | `-LingoFuseDart` | `-Force`、`-RunSmoke` |
| R | `setup_R_tests.ps1` | `-RuntimeDir`（或环境变量 `LINGOFUSE_RUNTIME`） | `-Force`、`-RunSmoke` |

每个脚本都支持 `-Help`，会打印完整用法、前置依赖、退出码说明。**在任何语言上，先跑 `-Help` 是最快的上手方式。**

---

## 附录 B — 测试标签含义

| 标签 | 含义 |
|------|------|
| `<Api>(app call)` | 通过 App 名称同步调用 `<Api>` |
| `<Api>(app async)` | 通过 App 名称异步调用 |
| `<Api>(app asyncSeq)` / `<Api>(app seq ...)` | 通过 App 名称异步顺序调用 |
| `<Api>(uid call)` | 通过 UID 同步调用 |
| `<Api>(uid async)` | 通过 UID 异步调用 |
| `<Api>(uid asyncSeq)` | 通过 UID 异步顺序调用 |
| `<Api>(p2pname call)` | 通过 P2P 组名同步调用 |
| `<Api>(p2pname async)` | 通过 P2P 组名异步调用 |
| `<Api>(p2pname asyncSeq)` | 通过 P2P 组名异步顺序调用 |
| `<Api>(app notify)` | 通过 App 名称发出通知（procedure） |
| `<Api>(app seq notify)` | 通过 App 名称顺序发出通知 |
| `<Api>(uid notify)` | 通过 UID 发出通知 |
| `<Api>(uid seq notify)` | 通过 UID 顺序发出通知 |
| `<Api>(p2pname notify)` | 通过 P2P 组名发出通知 |
| `<Api>(p2pname seq notify)` | 通过 P2P 组名顺序发出通知 |
| `service-initiated call` | service 主动调用 client 的回调测试 |
| `whoami` / `client identity probe` | client 身份探测 |
| `(stats)` （仅 Dart） | 通过 service 侧的统计 API 验证调用次数 |

---

**文档版本**: 1.0
**文档定位**: `code_decl_to_abi` 生成的 17 种目标语言的测试方法速查与实操指南。
**配套文档**: `code_decl_to_abi_USER_GUIDE.md`（端到端用户指南）、`code_decl_to_abi_OPERATIONS.md`（内部实现与扩展）、`pascal_code_abi_rule.md` 与 `C_code_abi_rule.md`（输入契约）。
**生成代码语言**: 英文。本文档语言: 中文。
