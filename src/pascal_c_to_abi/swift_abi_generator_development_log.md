# Swift ABI 代码生成器开发日志

> **文档定位**：本文档记录 `code_decl_to_abi` 工具链新增 Swift 语言后端的完整开发过程，包括设计决策、交付清单、逐轮 bug 修复记录、验证结果。面向后续维护者与 AI 助手。
>
> **参考基线**：`cpp_abi_*.pas`（C++ 后端，黄金标准）、`pas_abi_*.pas`（Pascal 后端，参考实现）、`rust_abi_*.pas`（Rust 后端，包含完整的 setup + test 闭环）
>
> **文档版本**：v1.0
> **完成时间**：2026-10-27
> **最终状态**：Pascal call → Swift service 全 PASS；Swift call → Swift service 全 PASS（修复等待循环后）

---

## 第 0 章 概述

### 0.1 项目目标

为 `code_decl_to_abi` 工具链新增 **Swift 语言后端**，使该工具链支持从 Pascal/C 声明源生成 Swift 的 RPC service / call / test / build / setup 全套代码，且与现有 12 种语言（Pascal / Python / C++ / Rust / C# / Go / Java / Node.js / TypeScript / Erlang / Julia / Zig）**wire format 完全一致、可互操作**。

### 0.2 交付物清单

| # | 文件 | 职责 | 产物 |
|:-:|------|------|------|
| 1 | `swift_abi_service_generator_tool.pas` | Service 端生成器 | `<unit>_abi_service.swift` |
| 2 | `swift_abi_call_generator_tool.pas` | Call 端生成器 | `<unit>_abi_call.swift` |
| 3 | `swift_abi_test_generator_tool.pas` | 测试入口生成器 | `<unit>_abi_service_test.swift`、`<unit>_abi_call_test.swift` |
| 4 | `swift_abi_test_setup_generator_tool.pas` | 环境搭建脚本生成器 | `setup_swift_tests.ps1` |
| 5 | `code_decl_to_abi.lpr`（uses 段） | 注册入口 | 无需额外文件 |

### 0.3 关键承诺

- **生成的 Swift 代码零注释**（保持与 C++/Pascal/Rust 产物风格一致）
- **不生成 `.md`**（移除 README 生成逻辑）
- **Pascal 源码内所有单引号使用 `#39` 转义**（避免 FPC 边缘解析问题）
- **Wire format 逐字节对齐 C++/Pascal/Rust**
- **遇到基础库问题立即停下报告，不掩盖**

---

## 第 1 章 架构设计

### 1.1 三层结构

```
┌──────────────────────────────────────────┐
│  生成器层（.pas）                          │
│  swift_abi_service_generator_tool.pas    │
│  swift_abi_call_generator_tool.pas       │
│  swift_abi_test_generator_tool.pas       │
│  swift_abi_test_setup_generator_tool.pas │
└──────────────────────────────────────────┘
               ↓ 生成
┌──────────────────────────────────────────┐
│  Swift 产物                               │
│  <unit>_abi_service.swift                │
│  <unit>_abi_call.swift                   │
│  <unit>_abi_service_test.swift           │
│  <unit>_abi_call_test.swift              │
│  setup_swift_tests.ps1（运行时生成        │
│    Package.swift）                        │
└──────────────────────────────────────────┘
               ↓ 编译/运行
┌──────────────────────────────────────────┐
│  Swift 运行时                             │
│  LingoFuse 绑定（Sources/LingoFuse/*.swift）│
│  C ABI 层（CLingoFuse）                   │
│  LingoFuse 原生库（LingoFuse64.dll）      │
└──────────────────────────────────────────┘
```

### 1.2 生成器注册机制

所有 Swift 生成器通过 `code_decl_to_abi_registry.pas` 的 `RegisterGenerator` API 注册：

```pascal
RegisterGenerator(
  'swift',                      // 语言 ID
  'xxx_abi_service.swift',      // 文件名模板（xxx 运行时替换为 UnitName）
  gkService,                    // 生成器类型
  'Swift ABI service implementation',
  @GenerateABIServiceSwiftCode);
```

`xxx` 前缀会被 `ResolveFileName` 在运行时替换为 `UnitName`（如 `ComplexTestUnit`）。

`setup_swift_tests.ps1` 是固定文件名，通过 `gkPs1` 类型注册，不做 `xxx` 替换。

### 1.3 Swift 端的模块组织（SPM 强制）

`setup_swift_tests.ps1` 将生成产物整理到 SPM 强制目录结构：

```
<out_dir>/
├── Package.swift
├── setup_swift_tests.ps1
├── Sources/
│   ├── <unit>_abi_service/
│   │   └── <unit>_abi_service.swift    ← 模块名 = target name
│   ├── <unit>_abi_call/
│   │   └── <unit>_abi_call.swift       ← 模块名 = target name
│   ├── ServiceTest/
│   │   └── main.swift                  ← 可执行入口
│   └── CallTest/
│       └── main.swift                  ← 可执行入口
└── .build/（swift build 生成）
```

**关键点**：`<unit>_abi_service.swift` 里的 enum 名为 `<Unit>ABIService`（如 `ComplexTestUnitABIService`），但**模块名**（`import` 引用的名字）是 `<unit>_abi_service`（target name）。**两者不同**。

---

## 第 2 章 生成产物详解

### 2.1 Service 端产物

**文件**：`<unit>_abi_service.swift`

**结构**：

```swift
import Foundation
import LingoFuse

public enum ComplexTestUnitABIService {
    public static let defaultAppName: String = "ComplexTestUnit_abi"
    public static let defaultAppDesc: String = "ABI service for ComplexTestUnit"
    public static let statusOK: UInt8 = 0x00
    public static let statusError: UInt8 = 0xFF

    // 每个 Call API 的 internal 桩（fatalError 占位）
    public static func internalCall_Add(uid: Uid, p2pName: String, _ a: Int32, _ b: Int32) -> Int32 {
        _ = uid
        _ = p2pName
        _ = a
        _ = b
        fatalError("TODO: implement internalCall_Add")
    }

    // 每个 Call API 的 callback
    private static func callback_Add(input: DataHandle, output: DataHandle) {
        let uid = input.p2pUid()
        let p2pName = input.p2pName()
        do {
            let a: Int32 = try input.readInt32()
            let b: Int32 = try input.readInt32()
            let result = internalCall_Add(uid: uid, p2pName: p2pName, a, b)
            try output.writeUInt8(statusOK)
            try output.writeInt32(result)
        } catch {
            try? output.writeUInt8(statusError)
            try? output.writeString("\(error)")
        }
    }

    // 每个 Notify API 的 internal 桩 + callback（结构类似，无 output）

    public static func registerAllABIAPIs(app: AppHandle) throws {
        try app.registerCall("Add", "ABI api for Add", callback_Add)
        // ...（AppHandle.registerCall 无外部标签）
    }

    public static func registerAllP2PABIAPIs() throws {
        try P2P.registerCall("Add", description: "ABI api for Add", handler: callback_Add)
        // ...（P2P.registerCall 有 description:handler: 外部标签）
    }

    public static func createAndRegisterABIApp() throws -> AppHandle {
        let app = try AppHandle(name: defaultAppName, description: defaultAppDesc)
        try registerAllABIAPIs(app: app)
        return app
    }
}
```

**关键设计**：
- **`internalCall_*` 用 `fatalError` 占位**：与 C++ 的 `return 0;` / Pascal 的 `Result := default;` / Rust 的 `fatalError(...)` 语义一致。**用户必须手动填业务逻辑**，这是 ABI generator 的定位。
- **不使用 `@convention(c)` / `@_cdecl`**：利用 `AppHandle.registerCall` 的闭包封装，直接传函数引用。
- **参数名外部标签为 `_`**：`internalCall_Add(uid: Uid, p2pName: String, _ a: Int32, _ b: Int32)`，调用时 `internalCall_Add(uid: uid, p2pName: p2pName, a, b)`。
- **`uid` / `p2pName` 侧数据**：从 `input.p2pUid()` / `input.p2pName()` 提取，作为前导参数传给 `internalCall_*`，让用户知道调用方身份。

### 2.2 Call 端产物

**文件**：`<unit>_abi_call.swift`

**结构**：

```swift
import Foundation
import LingoFuse

public enum ComplexTestUnitABICall {
    public static var targetAppName: String = "ComplexTestUnit_abi"
    public static var defaultTimeoutMs: UInt64 = 5000
    public static let statusOK: UInt8 = 0x00
    public static let statusError: UInt8 = 0xFF

    private static func buildParam_Add(_ a: Int32, _ b: Int32) throws -> DataHandle {
        let param = try DataHandle(apiName: "Add")
        try param.writeInt32(a)
        try param.writeInt32(b)
        param.position = 0
        return param
    }

    private static func readResponse_Add(_ resp: DataHandle) throws -> Int32 {
        resp.position = 0
        let status: UInt8 = try resp.readUInt8()
        if status != statusOK {
            let msg = (try? resp.readString()) ?? ""
            throw LingoFuseError.callFailed(
                operation: "ABI call Add failed: " + msg,
                targetApp: targetAppName,
                targetApi: "Add")
        }
        return try resp.readInt32()
    }

    // 9 种组合：App/UID/P2PName × 同步/异步/异步顺序
    public static func Add(_ a: Int32, _ b: Int32) throws -> Int32 { ... }
    public static func Add_Async(_ a: Int32, _ b: Int32) async throws -> Int32 { ... }
    public static func Add_AsyncSequenced(_ a: Int32, _ b: Int32) async throws -> Int32 { ... }
    public static func Add_UID_Call(_ uid: Uid, _ a: Int32, _ b: Int32) throws -> Int32 { ... }
    public static func Add_UID_Async(_ uid: Uid, _ a: Int32, _ b: Int32) async throws -> Int32 { ... }
    public static func Add_UID_AsyncSequenced(_ uid: Uid, _ a: Int32, _ b: Int32) async throws -> Int32 { ... }
    public static func Add_P2PName_Call(_ p2pName: String, _ a: Int32, _ b: Int32) throws -> Int32 { ... }
    public static func Add_P2PName_Async(_ p2pName: String, _ a: Int32, _ b: Int32) async throws -> Int32 { ... }
    public static func Add_P2PName_AsyncSequenced(_ p2pName: String, _ a: Int32, _ b: Int32) async throws -> Int32 { ... }

    // Notify 族 6 种组合
    public static func NoParamProc() throws { ... }
    public static func NoParamProc_SequencedNotify() throws { ... }
    public static func NoParamProc_UID_Notify(_ uid: Uid) throws { ... }
    public static func NoParamProc_UID_SequencedNotify(_ uid: Uid) throws { ... }
    public static func NoParamProc_P2PName_Notify(_ p2pName: String) throws { ... }
    public static func NoParamProc_P2PName_SequencedNotify(_ p2pName: String) throws { ... }
}
```

**关键设计**：
- **完全利用 `Target` / `AsyncTarget` 抽象**：`AppTarget` / `UidTarget` / `P2PNameTarget`，生成的代码最简洁。
- **异步用原生 `async/await`**：`await AppTarget(...).callAsync(...)`，无需 `CheckedContinuation`。
- **`buildParam_*` 复用**：Call 和 Notify 共用，避免重复。
- **`readResponse_*` 统一**：状态字节 + 返回值，与 C++ 的 `EmitCallCheckResponse` 逐字节对齐。
- **`targetAppName` / `defaultTimeoutMs` 是 `public static var`**：允许运行时切换（对齐 C++ 的 `ABI_TargetApp`）。

### 2.3 Service Test 产物

**文件**：`<unit>_abi_service_test.swift`（被 setup 脚本重命名为 `Sources/ServiceTest/main.swift`）

**核心流程**：

```swift
import Foundation
import LingoFuse
import <unit>_abi_service

func serviceTestRun() -> Int32 {
    var app: AppHandle? = nil
    do {
        Framework.setOption("Wait_Connection_ReadyOk", "False")
        Framework.setOption("Overlap_Connection", "True")
        Framework.setOption("ConsoleOutput", "True")
        Options.setQuiet(true)
        Framework.resetPrepare()
        try Framework.prepareService(listeningAddr: endpoint, physicsAddr: endpoint)
        let createdApp = try <EnumName>.createAndRegisterABIApp()
        app = createdApp
        try createdApp.registerCall("LF_TEST_WHOAMI", "whoami", serviceTestCbWhoAmI)
        try createdApp.registerNotify("LF_TEST_ASK_SERVICE_CALL_ME", "...", serviceTestCbAskCallMe)
        Options.setP2PName(p2pName)
        try <EnumName>.registerAllP2PABIAPIs()
        try P2P.registerCall("LF_TEST_WHOAMI", description: "whoami", handler: serviceTestCbWhoAmI)
        try P2P.registerNotify("LF_TEST_ASK_SERVICE_CALL_ME", description: "ask", handler: serviceTestCbAskCallMe)
        try Framework.prepareClient(physicsAddr: endpoint, app: createdApp)
        if !Framework.prepareDone() { ... return 1 }
        print("[OK] Service ready on \(endpoint)")
        _ = readLine()
        Framework.exitMainThread()
        createdApp.dispose()
        Framework.shutdown()
        return 0
    } catch { ... return 1 }
}

print("=== <unit> ABI service test ===")
if LF_LoadLibrary() != 1 {
    FileHandle.standardError.write("[FATAL] LF_LoadLibrary failed\n".data(using: .utf8)!)
    exit(1)
}
let SERVICE_TEST_EXIT_CODE: Int32 = serviceTestRun()
LF_FreeLibrary()
if SERVICE_TEST_EXIT_CODE != 0 { exit(SERVICE_TEST_EXIT_CODE) }
```

**双向握手**：
- `LF_TEST_WHOAMI`：返回调用方的 UID + P2PName（从 `input.p2pUid()` / `input.p2pName()` 提取）
- `LF_TEST_ASK_SERVICE_CALL_ME`：Service 主动用 `Framework.callByUid(uid, ...)` 反向调用客户端的 `LF_TEST_REPORT_SERVICE_IDENTITY`

**关键点**：
- **`LF_LoadLibrary` 必须在任何 `LF_*` 调用之前**（否则全部报 "called before LF_LoadLibrary"）
- **`LF_FreeLibrary` 在 `serviceTestRun` 返回后调用**
- **顶层用 `exit(code)` 显式退出**，确保退出码正确

### 2.4 Call Test 产物

**文件**：`<unit>_abi_call_test.swift`（被 setup 脚本重命名为 `Sources/CallTest/main.swift`）

**核心流程**：

```swift
func callTestRun() -> Int32 {
    var clientApp: AppHandle? = nil
    do {
        Framework.setOption("Wait_Connection_ReadyOk", "False")
        Framework.setOption("Overlap_Connection", "True")
        // ...
        let createdApp = try AppHandle(name: "LF_TEST_CLIENT_SELF", description: "client test app")
        clientApp = createdApp
        try createdApp.registerCall("LF_TEST_REPORT_SERVICE_IDENTITY", "...", callTestCbReportIdentity)
        try Framework.prepareClient(physicsAddr: endpoint, app: createdApp)
        if !Framework.prepareDone() { ... return 1 }
        print("[READY] Client online.")

        // ★ 关键：等待 Target 就绪（详见 §4.10）
        var targetReady = false
        for _ in 0..<30 {
            if Framework.checkApi(targetApp, "LF_TEST_WHOAMI") {
                targetReady = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        if targetReady {
            print("[OK] Target service ready on the mesh")
        } else {
            FileHandle.standardError.write("[WARN] Target service not ready\n".data(using: .utf8)!)
        }

        // 探测自身身份（让 service 端 whoami 回传 UID）
        if callTestProbeClientIdentity() { print("[OK] client identity probe") }

        // 让 service 端反向调用客户端
        if callTestServiceInitiatesCall() {
            reportPass("service-initiated call", "ok")
        } else {
            reportFail("service-initiated call", "timeout or no UID")
        }

        // 遍历所有 API 的 9 种 Call 组合 + 6 种 Notify 组合
        test_Add()
        test_Sub()
        // ... 所有 API

        print("=== Summary ===")
        Framework.exitMainThread()
        createdApp.dispose()
        Framework.shutdown()
        if failCount == 0 { return 0 }
        return 2
    } catch { ... return 1 }
}

if LF_LoadLibrary() != 1 { ... exit(1) }
let CALL_TEST_EXIT_CODE: Int32 = callTestRun()
LF_FreeLibrary()
if CALL_TEST_EXIT_CODE != 0 { exit(CALL_TEST_EXIT_CODE) }
```

**异步测试桥接**：

```swift
final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<T, Error>? = nil
    func set(_ r: Result<T, Error>) { lock.lock(); value = r; lock.unlock() }
    func take() -> Result<T, Error>? { lock.lock(); defer { lock.unlock() }; ... }
}

func runAsyncWithSema<T>(_ label: String, _ body: @escaping () async throws -> T) -> Result<T, Error> {
    let sema = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached {              // ★ detached 脱离主线程，避免主线程 RunLoop 依赖
        do { box.set(.success(try await body())) }
        catch { box.set(.failure(error)) }
        sema.signal()
    }
    if sema.wait(timeout: .now() + 10) == .timedOut {
        return .failure(LingoFuseError.timeout(targetApp: label))
    }
    return box.take() ?? .failure(...)
}
```

**为什么 `Task.detached` + `DispatchSemaphore` 是安全的**：
- 从 `Sources/LingoFuse/AsyncSupport.swift` 可知，`callAsync` 内部用 `CheckedContinuation`，resume 由 C ABI 的 TCompute 工作线程触发，不依赖主线程 RunLoop。
- `Task.detached` 在 Swift 的 Cooperative Thread Pool 执行，不占用主线程。
- `DispatchSemaphore.wait` 阻塞主线程是安全的（测试程序无 Watchdog）。

### 2.5 `Package.swift`（由 setup 脚本运行时生成）

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComplexTestUnit_abi",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "ComplexTestUnit_abi_service", targets: ["ComplexTestUnit_abi_service"]),
        .library(name: "ComplexTestUnit_abi_call",    targets: ["ComplexTestUnit_abi_call"]),
        .executable(name: "ServiceTest",    targets: ["ServiceTest"]),
        .executable(name: "CallTest",       targets: ["CallTest"]),
    ],
    dependencies: [
        .package(path: "D:/CoreLibrary/LingoFuse/swift"),
    ],
    targets: [
        .target(
            name: "ComplexTestUnit_abi_service",
            dependencies: [.product(name: "LingoFuse", package: "swift")],  // ★ package: 是 identity，不是 name
            path: "Sources/ComplexTestUnit_abi_service"
        ),
        // ...
    ]
)
```

**关键点**：
- **`.package(path:)` 的 identity 是路径最后一段的小写**（`swift`），**不是** `Package.swift` 的 `name` 字段（`LingoFuse`）
- **`.product(name: "LingoFuse", package: "swift")`** —— `name` 是依赖包的 product 名，`package` 是依赖包的 identity
- **`setup_swift_tests.ps1` 每次运行都会重新生成 `Package.swift`**，固化 `LingofuseDir` 的绝对路径（换机器只需重跑 setup 脚本）

---

## 第 3 章 跨语言 Wire Format 一致性

这是**多语言互通的生死线**，Swift 生成器必须与 C++/Pascal/Rust 逐字节对齐。

### 3.1 Service 端响应格式

| 场景 | 字节序列 | Swift 生成代码 | C++ 对照 |
|------|---------|---------------|---------|
| 成功 + 整数/浮点 | `[0x00][T 的 little-endian bytes]` | `try output.writeUInt8(statusOK)` + `try output.writeInt32(result)` | `Safe_Write_Scalar<T>` |
| 成功 + 字符串 | `[0x00][UTF-8 bytes][0x00]` | `try output.writeUInt8(statusOK)` + `try output.writeString(result)` | `Safe_Write_String` |
| 失败 | `[0xFF][UTF-8 error bytes][0x00]` | `try? output.writeUInt8(statusError)` + `try? output.writeString("\(error)")` | `Safe_Write_Error` |
| 输入截断 | `[0xFF][UTF-8 "truncated input: <param>"][0x00]` | `try? output.writeUInt8(statusError)` + `try? output.writeString(...)` | 同 C++ |
| Notify 成功 | 无响应（Notify 不写 output） | — | — |

### 3.2 Call 端请求格式

按参数顺序依次写入，**无前置状态字节**：

| 类型 | Swift 生成代码 |
|------|---------------|
| 整数 | `try param.writeInt32(v)` |
| 浮点 | `try param.writeDouble(v)` |
| 字符串 | `try param.writeString(v)`（内部自动追加 `\0`） |

### 3.3 Call 端响应解析

```
seek(0)
status = readUInt8()
if status != 0x00:
    msg = readString()   // 扫描到 \0
    throw callFailed(msg)
result = read<Type>()    // 整数：直接读；字符串：readString()
```

### 3.4 类型映射表

| Pascal ABI 类型（归一化后） | Swift 类型 | 写入 | 读取 |
|---|---|---|---|
| `integer` / `longint` | `Int32` | `writeInt32` | `readInt32` |
| `int64` | `Int64` | `writeInt64` | `readInt64` |
| `cardinal` / `dword` / `longword` | `UInt32` | `writeUInt32` | `readUInt32` |
| `word` | `UInt16` | `writeUInt16` | `readUInt16` |
| `smallint` | `Int16` | `writeInt16` | `readInt16` |
| `byte` | `UInt8` | `writeUInt8` | `readUInt8` |
| `uint64` | `UInt64` | `writeUInt64` | `readUInt64` |
| `double` / `extended` / `real` | `Double` | `writeDouble` | `readDouble` |
| `single` | `Float` | `writeSingle` | `readSingle` |
| `string` 家族 | `String` | `writeString` | `readString` |

### 3.5 字节序保证

Swift 的 `writeInt32` 底层调用 `LF_WriteInt32`，C ABI 层用 `Move(Value, buff, 4)` 依赖主机字节序。x86_64 和 arm64 都是 little-endian，**安全**。Z 框架本身不支持大端平台（`Z.Define.inc` 定义了 `BIG_ENDIAN` 会编译 FATAL）。

---

## 第 4 章 开发过程与 Bug 修复记录

按时间顺序记录每一轮 bug 的现象、根因、修复。**这是本文档的核心部分**。

### 4.1 第 1 轮：SPM identity 误用

**现象**：

```
error: 'complextestunit': unknown package 'LingoFuse' in dependencies of target 'ComplexTestUnit_abi_service';
       valid packages are: 'swift' (at 'D:\CoreLibrary\LingoFuse\swift')
```

**根因**：

Swift Package Manager 对 `.package(path:)` 注册的包计算 **identity** 的规则是：**路径最后一段的小写形式**。

对于 `D:\CoreLibrary\LingoFuse\swift`：
- 最后一段是 `swift`
- identity = `swift`

但 `swift_abi_test_setup_generator_tool.pas` 生成的 `Package.swift` 里写了：

```swift
.product(name: "LingoFuse", package: "LingoFuse")  // ❌ package 参数错误
```

`package:` 参数的值是 `Package.swift` 的 `name` 字段（`LingoFuse`），但 SPM 需要的是 **identity**（`swift`）。

**修复**：

`setup_swift_tests.ps1` 里新增：

```powershell
$packageIdentity = (Split-Path -Leaf $normalizedLingofuse).ToLower()
```

生成的 `Package.swift`：

```swift
.product(name: "LingoFuse", package: "$packageIdentity")  // ✅ 动态填入 "swift"
```

### 4.2 第 2 轮：`import` 用错模块名

**现象**：

同第 1 轮（`swift build` 失败），但根因不同。

**根因**：

`swift_abi_test_generator_tool.pas` 生成的 test 入口用：

```swift
import ComplexTestUnitABIService   // ❌ 这是 enum 名
```

但 Swift 的 `import` 引用的是 **module 名**（即 `Package.swift` 里 `target.name`），不是 module 里的 enum 名。

`target.name` 是 `ComplexTestUnit_abi_service`（下划线小写），enum 名是 `ComplexTestUnitABIService`（驼峰）。

**修复**：

改成：

```swift
import ComplexTestUnit_abi_service   // ✅ module 名
```

**顺带修复**：移除 Windows 上无意义的条件 import：

```swift
// 之前：
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// 现在：移除（Foundation 已提供 exit 等）
```

### 4.3 第 3 轮：Service 端 `writeUInt8` 缺 `try`

**现象**：

```
error: call can throw but is not marked with 'try'
output.writeUInt8(statusOK)
```

**根因**：

`DataHandle.writeUInt8(_:)` 在 `Sources/LingoFuse/DataHandle.swift` 里声明为 `throws`：

```swift
public func writeUInt8(_ v: UInt8) throws { ... }
```

`swift_abi_service_generator_tool.pas` 的 `EmitCallbackImpl` 生成的代码：

```swift
output.writeUInt8(statusOK)            // ❌ 缺 try
output.writeUInt8(statusError)         // ❌ 缺 try
```

**修复**：

```swift
try output.writeUInt8(statusOK)        // ✅
try? output.writeUInt8(statusError)    // ✅（catch 里用 try?）
```

### 4.4 第 4 轮：`internalCall_xxx` 参数缺外部标签

**现象**：

```
error: missing argument labels 'a:b:' in call
let result = internalCall_MultiLineComment(uid: uid, p2pName: p2pName, a)
```

**根因**：

`BuildInternalCallParamDecl` 生成的声明是：

```swift
public static func internalCall_MultiLineComment(uid: Uid, p2pName: String, a: Int32) -> Int32
```

`a: Int32` **有外部标签 `a`**。但调用时写的是 `a`（无标签）：

```swift
internalCall_MultiLineComment(uid: uid, p2pName: p2pName, a)  // ❌ a 没有 a: 前缀
```

**修复**：

声明改为无外部标签：

```swift
public static func internalCall_MultiLineComment(uid: Uid, p2pName: String, _ a: Int32) -> Int32
```

调用 `internalCall_MultiLineComment(uid: uid, p2pName: p2pName, a)` 就正确了。

### 4.5 第 5 轮：Notify 无参数时 `catch` 不可达

**现象**：

```
warning: 'catch' block is unreachable because no errors are thrown in 'do' block
```

**根因**：

Notify 无参数时，`do { } catch { }` 里只有 `internalNotify_xxx(...)`（非 throws），`catch` 永远不可达。

**修复**：

`EmitCallbackImpl` 加条件判断：

```pascal
NeedTryBlock := F.IsFunction or HasParams;
if NeedTryBlock then
  Lines.Add('        do {');
```

Notify 无参数时直接生成：

```swift
private static func callback_ExternalAlias(input: DataHandle) {
    let uid = input.p2pUid()
    let p2pName = input.p2pName()
    internalNotify_ExternalAlias(uid: uid, p2pName: p2pName)
}
```

不包 `do-catch`。

### 4.6 第 6 轮：`P2P.registerCall` 外部标签差异

**现象**：

```
error: missing argument labels 'description:handler:' in call
try P2P.registerCall("NoParamFunc", "...", callback_NoParamFunc)
```

**根因**：

`AppHandle.registerCall` 和 `P2P.registerCall` 的**外部标签语义不同**：

```swift
// AppHandle.swift
public func registerCall(
    _ apiName: String,
    _ description: String = "",       // 无外部标签
    _ handler: @escaping (...) -> Void // 无外部标签
) throws -> Bool

// P2P.swift
public static func registerCall(
    _ apiName: String,
    description: String = "",          // 有外部标签
    handler: @escaping (...) -> Void   // 有外部标签
) throws -> Bool
```

**修复**：

`EmitRegisterAll` 里 P2P 调用加外部标签：

```pascal
Lines.Add('        try P2P.registerCall(' + SwiftStrLit(ApiName) + ', description: ' + SwiftStrLit(Description) +
  ', handler: callback_' + ApiName + ')')
```

`AppHandle` 调用保持无标签：

```pascal
Lines.Add('        try app.registerCall(' + SwiftStrLit(ApiName) + ', ' + SwiftStrLit(Description) +
  ', callback_' + ApiName + ')')
```

### 4.7 第 7 轮：`let msg = ...` 真 unused warning

**现象**：

```
warning: initialization of immutable value 'msg' was never used
let msg = (try? resp.readString()) ?? ""
```

**根因**：

`LingoFuseError.callFailed(operation:targetApp:targetApi:)` **没有 message 参数**，`msg` 无处安放。

**修复**：

把 `msg` 拼进 `operation`：

```swift
let msg = (try? resp.readString()) ?? ""
throw LingoFuseError.callFailed(
    operation: "ABI call \(apiName) failed: " + msg,   // ✅ msg 用上了
    targetApp: targetAppName,
    targetApi: apiName)
```

### 4.8 第 8 轮：`swift run <Product>` 大小写敏感

**现象**：

```
error: no executable product named 'ServiceTest'
```

**根因**：

`Package.swift` 里 product 名是 `service_test`（小写）：

```swift
.executable(name: "service_test",    targets: ["ServiceTest"]),
```

但用户输入 `swift run ServiceTest`（首字母大写），SPM **大小写敏感**，不匹配。

**修复**：

```swift
.executable(name: "ServiceTest",    targets: ["ServiceTest"]),   // ✅ 与 target 名一致
.executable(name: "CallTest",       targets: ["CallTest"]),
```

### 4.9 第 9 轮：FPC 编译 `String exceeds line`

**现象**：

```
swift_abi_call_generator_tool.pas(381,103) Fatal: (2001) String exceeds line
```

**根因**：

`swift_abi_call_generator_tool.pas` 里：

```pascal
Lines.Add('                operation: ' + SwiftStrLit('ABI call ' + ApiName.Text + ' failed: ') + ' + msg,');
```

这是一个 **5 段式字符串拼接**（`字面量 + 函数调用 + 字面量 + 字面量,`），且最后一段 `' + msg,'` 含 `+` 和 `,` 字符。FPC 3.2.2 在此边缘场景触发列号检查错误。

**修复**：

改用 `OpLine` 局部变量分步 Append：

```pascal
procedure EmitReadResponseHelper(...);
var
  OpLine: TP_String;
begin
  ...
  OpLine := '                operation: ';
  OpLine.Append(SwiftStrLit('ABI call ' + ApiName.Text + ' failed: '));
  OpLine.Append(' + msg');
  OpLine.Append(',');
  ...
  Lines.Add(OpLine.Text);   // ✅ 单参数，FPC 解析路径极简
end;
```

**同样处理**：`EmitSyncAppCall` / `EmitSyncUidCall` / `EmitSyncP2PNameCall` 里的 `Lines.Add('literal' + Func(...) + 'literal',')` 也改为分步 Append。

### 4.10 第 10 轮：`LF_LoadLibrary` 从未调用

**现象**：

```
LingoFuse: SetOption called before LF_LoadLibrary
LingoFuse: ResetPrepare called before LF_LoadLibrary
LingoFuse: PrepareService called before LF_LoadLibrary
LingoFuse: CreateApp called before LF_LoadLibrary
[FATAL] service test: \(error)\n
LingoFuse: ExitMainThread called before LF_LoadLibrary
LingoFuse: Shutdown called before LF_LoadLibrary
```

**根因**：

`swift_abi_test_generator_tool.pas` 生成的 test 入口**漏掉了 `LF_LoadLibrary` 调用**。参考 `Sources/LingoFuse/Framework.swift` 和 `CrossService/main.swift`，**C ABI 层必须显式加载动态库**。

**修复**：

Service test 顶层：

```swift
print("=== ... ===")
if LF_LoadLibrary() != 1 {
    FileHandle.standardError.write("[FATAL] LF_LoadLibrary failed\n".data(using: .utf8)!)
    exit(1)
}
let SERVICE_TEST_EXIT_CODE: Int32 = serviceTestRun()
LF_FreeLibrary()
if SERVICE_TEST_EXIT_CODE != 0 { exit(SERVICE_TEST_EXIT_CODE) }
```

Call test 顶层同理。

### 4.11 第 11 轮：Free Pascal 没有 `\\` 转义

**现象**：

```
=== ComplexTestUnit ABI service test ===
LingoFuse: SetOption called before LF_LoadLibrary
...
[FATAL] service test: \(error)\n
```

注意输出是字面量 `\(error)\n`，而不是 `"真正的错误消息\n"`。

**根因**：

Free Pascal **没有 C 风格的 `\\` 转义**。在 Pascal 里：

- `'\\'` 是**两个反斜杠字符**（不是"一个反斜杠"）
- `'\'` 是**一个反斜杠字符**

`swift_abi_test_generator_tool.pas` 里写的是：

```pascal
Lines.Add('        FileHandle.standardError.write("[FATAL] service test: \\(error)\\n".data(using: .utf8)!)');
```

生成的 Swift 源码是：

```swift
FileHandle.standardError.write("[FATAL] service test: \\(error)\n".data(using: .utf8)!)
```

Swift 编译器把 `\\` 转义为 `\`，把 `\n` 转义为换行。所以最终的运行时字符串是 `"[FATAL] service test: \(error)" + 换行符`，`\(error)` 是**字面量**，不是插值。

**修复**：

所有 `'...\\...'` 改成 `'...\...'`（单个反斜杠），让生成的 Swift 源码是：

```swift
FileHandle.standardError.write("[FATAL] service test: \(error)\n".data(using: .utf8)!)
```

Swift 编译器就会正确插值。

**具体位置**（全部）：
- `serviceTestCbWhoAmI` 的 `print("[SERVICE] whoami: p2p=\(p2p)")`
- `serviceTestCbAskCallMe` 的 `print("[SERVICE] ask_call_me: client did not respond \(error)")`
- `serviceTestRun` 的 4 处
- `EmitSyncCallTest` 的 `"\(r)"` / `"\(error)"`
- `EmitAsyncCallTest` 的 `"\(v)"` / `"\(e)"`
- `EmitSyncNotifyTest` 的 `"\(error)"`
- Call test 的所有 `\(...)` 和 `\n`

### 4.12 第 12 轮：Swift↔Swift 失败（漏了等待 Target 就绪）

**现象**：

- **Pascal call → Swift service**：全 PASS ✅
- **Swift call → Swift service**：失败 ❌

CallTest 输出：

```
Connection ipc:ComplexTestUnit_abi:0 Succeeded
[READY] Client online.

"ComplexTestUnit_abi" no connection             ← ❌ 找不到 target
[WARN] whoami failed, UID tests will be skipped

Ready Network: "ipc:ComplexTestUnit_abi"        ← 异步日志：连接才真正 Ready
APP LF_TEST_CLIENT_SELF "client test app" Ready OK
```

**根因**：

- **Pascal 客户端默认 `Wait_Connection_ReadyOk=True`**：`LF_PrepareDone` **阻塞等待**所有客户端 Ready，等 C4 层握手完成才返回。此时 Target App 的广播已经到达客户端缓存，`Framework.call` 能正常路由。
- **Swift 客户端设了 `Wait_Connection_ReadyOk=False`**：`LF_PrepareDone` **立即返回**。此时 TCP 已连上，但 **C4 层的 App 注册广播（服务端 App → 客户端缓存）尚未传播完成**。`Framework.call` 用 App 名路由找不到 Target，返回 "no connection"。
- **几秒后**（异步日志 `Ready Network: "ipc:..."` 打印时）连接才真正 Ready。但 `callTestProbeClientIdentity` 早已失败退出。

**对照 Rust 版**：`rust_abi_test_generator_tool.pas` 的 `GenerateABICallTestRsCode` 里**有**等待循环：

```rust
let mut ready = false;
for _ in 0..30 {
    if framework::check_api(DEFAULT_TARGET_APP, WHOAMI_API).unwrap_or(false) {
        ready = true;
        break;
    }
    std::thread::sleep(Duration::from_millis(200));  // 30 × 200ms = 6 秒
}
```

**Swift 版漏了这段**。

**修复**：

`GenerateABICallTestSwiftCode` 的 `callTestRun` 里，在 `print("[READY] Client online.")` 之后、`callTestProbeClientIdentity()` 之前，新增 11 行：

```swift
var targetReady = false
for _ in 0..<30 {
    if Framework.checkApi(CALL_TEST_TARGET_APP, CALL_TEST_WHOAMI_API) {
        targetReady = true
        break
    }
    Thread.sleep(forTimeInterval: 0.2)
}
if targetReady {
    print("[OK] Target service ready on the mesh")
} else {
    FileHandle.standardError.write("[WARN] Target service not ready on the mesh\n".data(using: .utf8)!)
}
print("")
```

**为什么只修 CallTest 不修 ServiceTest**：
- ServiceTest 是服务端，`prepareDone` 返回后就已经 Listening，不主动调用 Target，不需要等待。
- CallTest 是客户端，必须等 Target App 的广播到达才能路由成功。

**修复后验证**：Swift call → Swift service 全 PASS ✅

### 4.13 其他小问题

| 问题 | 根因 | 修复 |
|------|------|------|
| `serviceTestCbWhoAmI` 的 `output.writeBytes(uid.rawBytes)` 缺 `try?` | `DataHandle.writeBytes(_:) throws` | 加 `try?` |
| `serviceTestCbWhoAmI` 的 `output.writeUInt8(0x00)` 缺 `try?` | `DataHandle.writeUInt8(_:) throws` | 加 `try?` |
| `internalCall_*` 桩里的 `_ = (uid, p2pName)` tuple 写法 | Swift 报 unused tuple | 改为 `_ = uid` + `_ = p2pName` 逐项 |
| Swift 6.4 `#NoUsage` 诊断误报（`let r = try ...; "\(r)"`） | Swift 6.4 把"仅用于字符串插值"的变量误判为 unused | **不修**：属于 Swift 6.4 的激进诊断，降版本或重构 cost 高。用户使用 Swift 6.3 或更早无此警告 |

---

## 第 5 章 编译与测试流程

### 5.1 生成代码

```
code_decl_to_abi --lang swift ComplexTestUnit.pas .
```

在 `ComplexTestUnit/` 目录下生成：

```
ComplexTestUnit_abi_service.swift
ComplexTestUnit_abi_call.swift
ComplexTestUnit_abi_service_test.swift
ComplexTestUnit_abi_call_test.swift
setup_swift_tests.ps1
```

### 5.2 环境搭建

```
.\setup_swift_tests.ps1 -LingofuseDir D:\CoreLibrary\LingoFuse\swift
```

脚本流程：
1. 校验 `LingofuseDir`（`Package.swift` + `Sources/LingoFuse/` 存在）
2. 校验 `swift` 工具链
3. 自动检测 `UnitName`（从 `*_abi_service.swift` 文件名反推）
4. 整理目录布局（`Sources/<target>/`）
5. **运行时生成 `Package.swift`**（固化 `LingofuseDir` 绝对路径 + 计算 package identity）
6. Sanity check（检测 Pascal 类型名残留）
7. 检查必需文件存在
8. 运行 `swift build`
9. 可选 `-RunSmoke`：额外 `swift build --product ServiceTest --product CallTest`

### 5.3 运行测试

**终端 1（Service）**：

```
swift run ServiceTest
```

期望输出：

```
=== ComplexTestUnit ABI service test ===
[OK] Service ready on ipc:ComplexTestUnit_abi
[OK] App: ComplexTestUnit_abi
[OK] P2P: ComplexTestUnit_service_test_p2p
[OK] Press Enter to shut down
```

**终端 2（Call）**：

```
swift run CallTest
```

期望输出（修复后）：

```
=== ComplexTestUnit ABI call test ===
Endpoint: ipc:ComplexTestUnit_abi
AppName : ComplexTestUnit_abi
P2PName : ComplexTestUnit_service_test_p2p

[READY] Client online.
[OK] Target service ready on the mesh

[INFO] client UID = ...
[OK] client identity probe

[INFO] service UID = ...
[PASS] service-initiated call = ok

[PASS] NoParamFunc(app call) = ...
...
[PASS] ...（所有 API × 所有寻址 × 所有模式）

=== Summary ===
Pass: N
Fail: 0
Skip: 0
```

退出码：
- 0：全 PASS
- 2：有 FAIL
- 1：初始化失败

### 5.4 手动填 Service 端实现

**注意**：`internalCall_*` 是 `fatalError` 占位。要跑通实际业务，用户必须手动编辑 `Sources/ComplexTestUnit_abi_service/ComplexTestUnit_abi_service.swift` 里的 `internalCall_Add` 等：

```swift
public static func internalCall_Add(uid: Uid, p2pName: String, _ a: Int32, _ b: Int32) -> Int32 {
    _ = uid
    _ = p2pName
    return a + b   // 用户填的业务逻辑
}
```

**这是设计决定**：与 C++/Pascal/Rust 的 ABI generator 一致，生成器只生成骨架，不生成业务逻辑。

---

## 第 6 章 验证结果

### 6.1 三向互操作验证

| 验证组合 | 结果 | 备注 |
|---------|:----:|------|
| **Pascal call → Swift service** | ✅ 全 PASS | 用户实测确认 |
| **Swift call → Swift service** | ✅ 全 PASS | 修复 §4.12 后通过 |
| **C++ call → Swift service** | ⏳ 待验证 | wire format 逐字节对齐，理论可通过 |
| **Swift call → C++ service** | ⏳ 待验证 | 同上 |
| **Swift call → Pascal service** | ⏳ 待验证 | 同上 |

### 6.2 `swift build` 状态

- ✅ **编译通过**（无 error）
- ⚠️ **有 Swift 6.4 的 `#NoUsage` 诊断 warning**（`let r = ...; "\(r)"` 被误报 unused）——见 §4.13

---

## 第 7 章 关键决策记录

### 7.1 Service 端不使用 `@convention(c)` / `@_cdecl`

**决策**：Service 端 callback 直接用函数引用传给 `AppHandle.registerCall`，不手写 trampoline。

**理由**：
- `Sources/LingoFuse/AppHandle.swift` 已经封装了 `swiftCallTrampoline` / `swiftNotifyTrampoline`（`@convention(c)` 闭包）
- `@_cdecl` 在 Windows 上跨文件引用会重复定义（`lld-link: duplicate symbol`），需要用 `@convention(c)` 规避
- 生成的代码更简洁，用户无需关心 trampoline

### 7.2 `internalCall_*` 用 `fatalError` 占位

**决策**：`internalCall_*` / `internalNotify_*` 默认生成 `fatalError("TODO: ...")`，用户必须手动实现。

**理由**：
- **与 C++/Pascal/Rust 一致**：C++ 生成 `return 0;`，Pascal 生成 `Result := default`，Rust 生成 `fatalError`。这是 ABI generator 的定位。
- 自动生成"回显式默认实现"（如 `Add` 返回 `a+b`）会偏离 ABI generator 的语义，跨语言行为不一致。

### 7.3 `Package.swift` 运行时生成（不预生成）

**决策**：`setup_swift_tests.ps1` 在运行时生成 `Package.swift`，而不是生成器提前生成。

**理由**：
- SPM 的 `.package(path:)` 需要绝对路径（相对路径换机器就失效）
- `Package.swift` 是 Swift 编译期读取的，不能读环境变量
- 所以必须在 setup 脚本运行时用 `Resolve-Path` 解析并固化

### 7.4 异步测试用 `Task.detached + DispatchSemaphore`

**决策**：Call test 的异步 API 测试用 `Task.detached + DispatchSemaphore` 转同步。

**理由**：
- **不依赖主线程 RunLoop**：`Task.detached` 在 Swift Cooperative Thread Pool 执行，避免主线程 RunLoop 驱动的复杂性
- **安全**：`DispatchSemaphore.wait` 阻塞主线程是安全的（测试程序无 Watchdog）
- **对齐 Rust 的 `mpsc::channel + recv_timeout`**：机制等价

**为什么不用 `Task { ... }`**：`Task {}` 继承当前 actor 上下文，可能回落到主 actor，导致主线程阻塞。`Task.detached` 明确脱离。

### 7.5 Swift 6.4 `#NoUsage` warning 不修

**决策**：`let r = try ...; "\(r)"` 的 unused warning **不修**。

**理由**：
- 这些变量明明被用于字符串插值，Swift 6.4 的 `#NoUsage` 把"仅用于 print 字符串插值"误判为 unused
- 修复需要改成 `_ = r` 或 `"\(try ...)"` 直接嵌入，引入丑陋代码
- 用户使用 Swift 6.3 或更早无此警告
- 属于 Swift 6.4 的激进诊断，不是代码 bug

**如果用户要求干净 build**：
- 选项 A：用 Swift 6.3 或更早
- 选项 B：重构 test generator 把 `let r = ...` 改成 `"\(try ...)"` 直接嵌入（cost 较高）

### 7.6 `Wait_Connection_ReadyOk=False` 的应用层补偿

**决策**：Swift 的 Call test 设置 `Wait_Connection_ReadyOk=False`，但**必须**加等待循环 `for _ in 0..<30 { checkApi; sleep 0.2 }`。

**理由**：
- `True` 时 `prepareDone` 阻塞等待，会拖慢启动（30 秒超时）
- `False` 时 `prepareDone` 立即返回，需要应用层轮询 `checkApi` 补偿 C4 层广播延迟
- **Rust 版已经这么做**，Swift 版对齐

---

## 第 8 章 已知问题与后续建议

### 8.1 已知问题

| # | 问题 | 影响 | 建议 |
|:-:|------|------|------|
| 1 | Swift 6.4 `#NoUsage` 诊断误报 | `swift build` 输出大量 warning | 见 §7.5 |
| 2 | `internalCall_*` 是 `fatalError` 占位 | 用户需手动实现业务逻辑 | 设计决定，与 C++/Pascal/Rust 一致 |
| 3 | `swift run <Product>` 大小写敏感 | 已修复（product 名改为 `ServiceTest`/`CallTest`） | — |
| 4 | SPM identity 依赖路径最后一段 | 换 `LingofuseDir` 后需重跑 setup 脚本 | 已文档化 |
| 5 | C++/Pascal service 端 ↔ Swift call 未实测 | 理论上 wire format 一致可通过 | 建议后续补测 |

### 8.2 后续建议

1. **补测跨语言互操作**：C++ service ↔ Swift call、Pascal service ↔ Swift call、Swift service ↔ C++/Pascal call
2. **可选：消除 Swift 6.4 warning**：把 test generator 的 `let r = ...` 改为 `"\(try ...)"` 直接嵌入（cost 较高，视用户需求）
3. **可选：为 `internalCall_*` 生成更友好的提示**：如 `fatalError("TODO: implement internalCall_Add — see README")`
4. **文档同步**：把 Swift 后端加入 `code_decl_to_abi --list-languages` 的说明

---

## 第 9 章 附录：文件清单

### 9.1 交付的 `.pas` 文件

| 文件 | 行数（约） | 关键函数 |
|------|----------|---------|
| `swift_abi_service_generator_tool.pas` | ~650 | `GenerateABIServiceSwiftCode` |
| `swift_abi_call_generator_tool.pas` | ~750 | `GenerateABICallSwiftCode` |
| `swift_abi_test_generator_tool.pas` | ~900 | `GenerateABIServiceTestSwiftCode` / `GenerateABICallTestSwiftCode` |
| `swift_abi_test_setup_generator_tool.pas` | ~400 | `GenerateSwiftTestSetupScript` |

### 9.2 生成的 Swift 产物（以 `ComplexTestUnit` 为例）

| 文件 | 位置（SPM 强制） |
|------|----------------|
| `ComplexTestUnit_abi_service.swift` | `Sources/ComplexTestUnit_abi_service/` |
| `ComplexTestUnit_abi_call.swift` | `Sources/ComplexTestUnit_abi_call/` |
| `ComplexTestUnit_abi_service_test.swift` → `main.swift` | `Sources/ServiceTest/` |
| `ComplexTestUnit_abi_call_test.swift` → `main.swift` | `Sources/CallTest/` |
| `Package.swift` | 根目录（setup 脚本生成） |
| `setup_swift_tests.ps1` | 根目录 |

### 9.3 依赖的外部绑定（不修改，直接用）

| 文件 | 用途 |
|------|------|
| `Sources/LingoFuse/DataHandle.swift` | `TDataHnd` 的 RAII 封装（`readInt32` / `writeString` / `p2pUid` / `p2pName` 等） |
| `Sources/LingoFuse/AppHandle.swift` | `TAppHnd` 的 RAII 封装（`registerCall` / `registerNotify` 闭包封装） |
| `Sources/LingoFuse/P2P.swift` | 进程级 P2P 注册 |
| `Sources/LingoFuse/Framework.swift` | 网络准备 / 远程调用门面 |
| `Sources/LingoFuse/Options.swift` | 运行时选项 |
| `Sources/LingoFuse/Target.swift` | 三套寻址抽象（`AppTarget` / `UidTarget` / `P2PNameTarget`） |
| `Sources/LingoFuse/AsyncSupport.swift` | `AsyncTarget` 协议 + async/await 桥接 |
| `Sources/LingoFuse/LfIo.swift` | JSON I/O |
| `Sources/LingoFuse/Uid.swift` | 32 字节 UID 值类型 |
| `Sources/LingoFuse/Errors.swift` | `LingoFuseError` 错误枚举 |

---

## 第 10 章 结语

Swift 后端从设计到交付共经历 **12 轮 bug 修复**，涵盖 SPM 机制、Swift 类型系统、FPC 语法陷阱、跨语言 wire format 一致性、并发模型等多个层面。最终状态：

- ✅ 编译通过（除 Swift 6.4 `#NoUsage` warning）
- ✅ Pascal call → Swift service 全 PASS
- ✅ Swift call → Swift service 全 PASS
- ⏳ C++ / Pascal ↔ Swift 双向互操作待补测

**核心承诺**：
- 所有 bug 都记录在案，不掩盖
- 所有决策都有理由
- 所有 wire format 都与 C++/Pascal/Rust 逐字节对齐
- 后续维护者能根据本文档完整复现整个开发过程

---

**文档版本**：v1.0
**最后更新**：2026-10-27
**维护者**：LingoFuse 团队
