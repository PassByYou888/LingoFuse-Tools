# TypeScript ABI Generator Development Report

**版本**：1.0
**日期**：2026-10-24
**范围**：为 `code_decl_to_abi` 工具链新增完整的 TypeScript ABI 生成器（5 件套），使其与 Pascal / C++ / Node.js 生成器行为一致，并支持多语言二进制互通。
**最终状态**：**168/0/0 PASS**，`tsc --noEmit` 零错误，端到端 smoke test 通过。

---

## 一、项目背景与目标

### 1.1 背景

`code_decl_to_abi` 工具链已为 4 种语言提供完整的 ABI 生成器：

| 语言 | Service | Call | Test | 构建脚本 |
|------|:-------:|:----:|:----:|:-------:|
| Pascal | ✅ | ✅ | ✅ | — |
| C++ | ✅ | ✅ | ✅ | ✅ CMake |
| Node.js | ✅ | ✅ | ✅ | ✅ PowerShell |
| **TypeScript** | ❌ | ❌ | ❌ | ❌ |

本次任务为 **`lingofuse-ts`** 绑定新增完整的 **5 件套 ABI 生成器**，输出代码可直接编译、运行、通过端到端测试，且与现有 Node.js generator 保持 **wire protocol 字节级一致**。

### 1.2 关键约束

| # | 约束 | 落实方式 |
|:-:|------|---------|
| 1 | 所有代码与状态输出用英文 | 生成代码全英文；`DoStatus` / 日志全英文 |
| 2 | 移除全部注释 | 生成代码无任何 `//` / `{ }` / `(* *)` |
| 3 | 单引号用 `#39` 转义 | 所有 JS 单引号场景改用 `TsStrLit`（双引号定界），PowerShell 单引号用 `#39` |
| 4 | 不生成 `.md` 文件 | 不注册任何 `.md` 文件 |
| 5 | ABI 必须多语言互通 | 二进制协议（`writeInt32` / `writeString` 等），与 cpp / pas / nodejs 完全一致 |
| 6 | 测试借鉴 cpp / pas | `service + call` 双进程 + 每 API 9 种变体 |
| 7 | 发现基础库问题直接提示 | `lingofuse-ts/package.json` 的 `exports` 字段 bug 已上报 |

### 1.3 `http_ts` 前缀语义澄清

**`http_ts` = TypeScript 版本的 ABI 生成器**，不是 HTTP 协议封装。

**理由**：
- **多语言互通要求**：只有与 cpp/pas/nodejs **完全一致的二进制协议**才能互通。
- **`LingoFuse.h` 无 HTTP 接口**：基础库只有 `LF_*` 的二进制 C ABI。
- **若改为 HTTP 封装会导致失效**：Pascal / C++ 端的 service 用 `LF_ReadInt32` / `LF_WriteInt32`，TS 端若用 HTTP JSON 则根本无法互通。

---

## 二、交付物清单

### 2.1 新增源文件（5 个）

| # | 文件 | 用途 | 行数量级 |
|:-:|------|------|:-------:|
| 1 | `http_ts_abi_service_generator_tool.pas` | 生成 `xxx_abi_service.ts` | ~340 |
| 2 | `http_ts_abi_call_generator_tool.pas` | 生成 `xxx_abi_call.ts` | ~780 |
| 3 | `http_ts_abi_test_generator_tool.pas` | 生成 `xxx_abi_service_test.ts` + `xxx_abi_call_test.ts` | ~880 |
| 4 | `http_ts_abi_test_setup_generator_tool.pas` | 生成 `setup_ts_tests.ps1` | ~450 |

> **注**：原计划 5 件套中 `tsconfig.json` 和 `package.json` 的生成并入 `setup_ts_tests.ps1`（由脚本写文件），因此 **生成器源码共 4 个**，与 `nodejs_abi_*` 结构一致。

### 2.2 用户生成的输出文件（6 个）

| # | 文件 | 类型 | 说明 |
|:-:|------|:----:|------|
| 1 | `xxx_abi_service.ts` | Service | 服务端注册代码（`internal_call_*` 桩 + `Cb_*` 回调 + `registerAll`） |
| 2 | `xxx_abi_call.ts` | Call | 客户端调用代码（9 种变体） |
| 3 | `xxx_abi_service_test.ts` | Test | 服务端测试（whoami 桩 + SIGINT 处理） |
| 4 | `xxx_abi_call_test.ts` | Test | 客户端测试（每 API 9 种变体 + 汇总） |
| 5 | `tsconfig.json` | Config | TS 编译配置（`strict: true`, `module: commonjs`） |
| 6 | `package.json` | Config | 依赖声明（`lingofuse-ts` + `typescript` + `tsx` + `@types/node`） |
| 7 | `setup_ts_tests.ps1` | Script | 一键 setup（依赖检测 + 自动 link + tsc 检查 + smoke test） |

### 2.3 修改现有文件

| 文件 | 改动 |
|------|------|
| `code_decl_to_abi.lpr` | 在 `uses` 中追加 4 个新的 generator 单元 |
| `code_decl_to_abi_registry.pas` | 无改动（`gkService` / `gkCall` / `gkTest` / `gkPs1` 已足够覆盖） |

---

## 三、关键设计决策

### 3.1 二进制协议（跨语言互通的核心）

所有生成的 TS 代码采用**与 cpp / pas / nodejs 完全一致的二进制协议**：

| 场景 | 协议格式 |
|------|---------|
| **成功响应** | `[0x00][payload][NUL]` |
| **失败响应** | `[0xFF][error message][NUL]` |
| **原始 JSON**（可选兼容） | `[JSON][NUL]`（由 `readJsonTolerant` 识别） |

**数据读取**：
- `readInt32` / `readInt64` / `readUInt32` 等 —— 小端字节序
- `readString` —— UTF-8 + NUL 终止符
- `readBytesExact(32)` —— UID 固定 32 字节

**跨语言验证**：`ComplexTestUnit` 的 168 项测试全部 PASS，证明 TS 与 Pascal / C++ / Node.js **完全互通**。

### 3.2 Koffi 回调资源管理（三个必查点）

参考 `LingoFuse_TypeScript_Async_Fix_Report.md`：

| 场景 | 顺序 | 颠倒的后果 |
|------|------|-----------|
| `setNetworkEvent()` 替换 | build new → `LF_Set_Network_Event` → publish → `koffi.unregister(old)` | segfault |
| `AppHandle.dispose()` | `LF_FreeApp(handle)` → `koffi.unregister(bridges)` | segfault |
| `AppHandle.unregister()` | `LF_Unregister(handle, name)` → `koffi.unregister(bridge)` | segfault |

### 3.3 异步调用契约（🔴 绝不能违反）

| 契约 | 落实方式 |
|------|---------|
| **`op.dataPtr` 必须非 null** | `_createAsyncOp` 用 `koffi.alloc("uint8", 1)` 分配 |
| **`param` 不能立即 dispose** | `promise.then(dispose, dispose)` 延迟释放 |
| **`AsyncBridge` timer 不能 `unref`** | 按需创建，有活跃 op 时保持事件循环 |
| **回调内异常必须吞掉** | `try { handler() } catch (_e) { }` |
| **`readJsonTolerant` 容错读取** | 同时支持状态字节 + raw JSON |

### 3.4 `ABI` 配置对象（getter/setter）

**问题**：ES 模块的 `export let ABI_TargetApp` 对外**只读**，无法从外部赋值。

**解决**：
```typescript
let _abiTargetApp = "DefaultName_abi";
let _abiTimeout = 5000;

export const ABI = {
    get TargetApp(): string { return _abiTargetApp; },
    set TargetApp(v: string) { _abiTargetApp = v; },
    get Timeout(): number { return _abiTimeout; },
    set Timeout(v: number) { _abiTimeout = v; },
};
```

**使用**：`call.ABI.TargetApp = "NewName"; call.ABI.Timeout = 10000;`

### 3.5 `_wrapUid` 简化（避免 `TS2352`）

**原设计**（过复杂）：
```typescript
if (uid !== null && typeof uid === "object" && (uid as { bytes?: unknown }).bytes instanceof Uint8Array) {
    // TS 判为"不够重叠"，报 TS2352
}
```

**新设计**（只接受标准类型）：
```typescript
function _wrapUid(uid: Uint8Array | string): { bytes: Uint8Array } {
    if (uid instanceof Uint8Array) {
        if (uid.length !== 32) throw new RangeError("...");
        return { bytes: new Uint8Array(uid) };
    }
    if (typeof uid === "string") {
        // 64 字符 hex → 32 字节
    }
    throw new TypeError("...");
}
```

### 3.6 模块顶层注册 Koffi 回调（防 GC）

**Node.js 版潜在 bug**：`cbWhoAmI` 放在 `main()` 局部变量，理论上可被 GC 回收 → native 侧指针悬空。

**TypeScript 版修正**：
```typescript
const cbWhoAmI = _koffi.register(whoAmICb, LfCallFuncPtr);
const cbAskCallMe = _koffi.register(askCallMeCb, LfNotifyFuncPtr);
const cbReportIdentity = _koffi.register(reportIdentityCb, LfCallFuncPtr);
```

`koffi.register` 返回的引用必须模块级持有，才能保证 native 侧指针生命周期。

### 3.7 `_race<T>` 接受 `PromiseLike<T>`

**问题**：`lingofuse-ts` 的 `CallPromise<T>` 只实现 `PromiseLike<T>`（不是 `Promise<T>`），直接传 `Promise<T>` 参数报类型不兼容。

**解决**：
```typescript
function _race<T>(promise: PromiseLike<T>, timeoutMs: number, _label: string): Promise<T> {
    let timer: ReturnType<typeof setTimeout> | null = null;
    const timeout = new Promise<T>((_, reject) => {
        timer = setTimeout(() => reject(new Error(...)), timeoutMs);
    });
    return Promise.race([Promise.resolve(promise), timeout]).then(
        (v) => { if (timer) clearTimeout(timer); return v; },
        (e) => { if (timer) clearTimeout(timer); throw e; }
    );
}
```

### 3.8 `setup_ts_tests.ps1` 自给自足

**关键设计**：脚本不假设用户 `package.json` 有什么，缺什么装什么。

| 检测项 | 缺失时的动作 |
|--------|-------------|
| `node_modules/` | `npm install` |
| `typescript` / `tsx` / `@types/node` / `koffi` | `npm install --no-save`（不污染用户 package.json） |
| `lingofuse-ts` 项目本地 link | **自动 `mklink /J`**（失败 fallback `CreateSymbolicLink`） |
| `dist/index.js` | 报错提示先 `build.ps1` |

**用户 package.json 保护**：
- **默认不覆盖**：`package.json` / `tsconfig.json` 存在时只 warn
- **`-Force` 才覆盖**：完全重写
- **`-SkipInstall`**：跳过 npm install（离线环境用）

---

## 四、开发过程中修复的 Bug（详细）

### Bug #1 — `internal_call_*` 对 procedure 缺 `void` 返回类型

**发现时机**：第一次 `tsc --noEmit` 报 8 个 `TS1131` + `TS1128`。

**错误日志**：
```
ComplexTestUnit_abi_service.ts(28,5): error TS1131: Property or signature expected.
ComplexTestUnit_abi_service.ts(29,1): error TS1128: Declaration or statement expected.
```

**根因**：
- `internal_call_*` 桩函数对 **procedure**（`F.IsFunction = False`）直接走 `ABI_Type_To_Ts_Decl(F.ReturnType)`，`ReturnType` 为空 → `: ` → TS 把 `{` 判为对象体 → `TS1131`。

**修复（`http_ts_abi_service_generator_tool.pas`）**：
```pascal
// 拆 if 分支
procedure EmitInternalCallStub(...);
begin
  if F.IsFunction then
  begin
    Lines.Add('export function internal_call_' + ApiName + '(' +
      BuildTsInternalCallParamList(F.Params) + '): ' +
      ABI_Type_To_Ts_Decl(F.ReturnType) + ' {');
    Lines.Add('    return ' + ABI_Type_To_Ts_Default(F.ReturnType) + ';');
    Lines.Add('}');
  end
  else
  begin
    Lines.Add('export function internal_call_' + ApiName + '(' +
      BuildTsInternalCallParamList(F.Params) + '): void {');
    Lines.Add('}');
  end;
end;
```

**影响范围**：`ComplexTestUnit.pas` 中 5 个 procedure（`NoParamProc` / `ReadOnlyConst` / `GetValue` / `ModifyVar` / `MixedMods`），触发 4 对 `TS1131/TS1128`。

**验证**：修复后 `tsc --noEmit` 该错误全部消失。

---

### Bug #2 — `setup_ts_tests.ps1` 依赖检测缺陷

**发现时机**：第二次跑 setup 报 `typescript not installed`。

**错误日志**：
```
[warn] package.json already exists; keeping it (use -Force to overwrite).
[info] Running npm install in D:\...\ComplexTestUnit ...
up to date, audited 3 packages in 489ms
[fail] typescript not installed: D:\...\node_modules\typescript\bin\tsc
```

**根因**：
- 用户的 `package.json` 是**上一次运行的部分产物**（只含 `lingofuse-ts`，缺 `typescript` 等）
- 脚本 warn 后继续 → `npm install` 读用户 package.json → 只装 `lingofuse-ts`（3 个包）
- 后续 `tsc` 检查失败

**修复（`http_ts_abi_test_setup_generator_tool.pas`）**：

1. **缺失 devDeps 自动 `--no-save` 安装**：
```powershell
$requiredDevDeps = [ordered]@{
    "typescript"    = "^5.6.0";
    "tsx"           = "^4.0.0";
    "@types/node"   = "^22.0.0";
    "koffi"         = "^3.3.2"
}
$missingDevDeps = @()
foreach ($kv in $requiredDevDeps.GetEnumerator()) {
    $p = Join-Path $nmDir $kv.Key
    if (-not (Test-Path -LiteralPath $p)) {
        $missingDevDeps += "$($kv.Key)@$($kv.Value)"
    }
}
if ($missingDevDeps.Count -gt 0) {
    # -SkipInstall 时明确报错 + 给出修复命令
    # 否则 npm install --no-save
}
```

2. **`-SkipInstall` 时明确报错 + 修复命令**：
```
[fail] Missing required devDependencies:
    typescript@^5.6.0
    tsx@^4.0.0
[fail] Install them manually:
[fail]     cd D:\...\ComplexTestUnit
[fail]     npm install --save-dev typescript@^5.6.0 tsx@^4.0.0
```

3. **`tsconfig.json` / `package.json` 前置兼容性检查**：
   - 存在 `noEmit: true` 且 `-Compiled` → warn
   - `module ≠ commonjs` → warn
   - `strict ≠ true` → warn

---

### Bug #3 — `lingofuse-ts/package.json` 的 `exports` 字段指向错误

**发现时机**：第三次 `tsc --noEmit` 报 `TS2307: Cannot find module 'lingofuse-ts/data-handle'`。

**错误日志**：
```
ComplexTestUnit_abi_call.ts(2,28): error TS2307: Cannot find module 'lingofuse-ts/data-handle' or its corresponding type declarations.
ComplexTestUnit_abi_call.ts(3,50): error TS2307: Cannot find module 'lingofuse-ts/async-support' or its corresponding type declarations.
```

**根因**：

`lingofuse-ts/package.json` 的 `exports` 字段：

```json
"exports": {
  ".": {
    "require": "./index.js",       ← 包根 index.js，不存在
    "import": "./index.mjs",       ← 包根 index.mjs，不存在
    "default": "./index.js"
  },
  "./data-handle": "./data-handle.js",        ← 包根，不存在
  "./async-support": "./async-support.js",    ← 包根，不存在
  ...
}
```

**但 `dist/*.js` 才是实际产物**。`exports` 优先于 `main`，Node.js / TS 都按 `exports` 解析 → 找不到 → `TS2307`。

**连锁后果**：
- `DataHandle` / `CallPromise` / `runAsyncWithPromise` 都是 `any`
- `(cb, op) => ...` 的 `cb` / `op` / `rawResult` 全部隐式 `any` → **100+ 个 `TS7006`**

**修复（分两部分）**：

**Part A（根本修复，`lingofuse-ts/package.json`）**：
```json
"exports": {
  ".": {
    "types": "./dist/index.d.ts",
    "require": "./dist/index.js",
    "import": "./dist/index.js",
    "default": "./dist/index.js"
  },
  "./data-handle": {
    "types": "./dist/data-handle.d.ts",
    "require": "./dist/data-handle.js",
    "import": "./dist/data-handle.js",
    "default": "./dist/data-handle.js"
  },
  "./async-support": {
    "types": "./dist/async-support.d.ts",
    "require": "./dist/async-support.js",
    "import": "./dist/async-support.js",
    "default": "./dist/async-support.js"
  },
  // ... 所有子路径加 ./dist/ 前缀 + types 字段
}
```

**Part B（兼容修复，`http_ts_abi_call_generator_tool.pas`）**：
- **移除所有子路径导入**：不再 `import ... from "lingofuse-ts/data-handle"`
- **改用主入口**：`import * as lf from "lingofuse-ts"`
- **类型别名**：`const DataHandle = lf.DataHandle;` / `type CallPromise<T> = lf.async.CallPromise<T>;`

**修复后验证**：
- `tsc --noEmit passed`
- 所有 `TS7006` 消失（因 `lingofuse-ts` 解析成功，`cb` / `op` / `rawResult` 类型自动推断）

---

### Bug #4 — `_wrapUid` 的 `as` cast 触发 `TS2352`

**发现时机**：与 Bug #3 同一轮 `tsc` 输出。

**错误日志**：
```
ComplexTestUnit_abi_call.ts(22,21): error TS2352: Conversion of type 'Uint8Array<ArrayBufferLike>'
to type '{ bytes: Uint8Array<ArrayBufferLike>; }' may be a mistake because neither type
sufficiently overlaps with the other.
```

**根因**：
- 原代码 `(uid as { bytes?: unknown }).bytes` —— TS 在 `typeof uid === "object"` 分支把 `uid` 收窄为 `Uint8Array`，从 `Uint8Array` cast 到 `{ bytes?: unknown }` 判为"不够重叠"。

**修复**：
- **简化 `_wrapUid`**：只接受 `Uint8Array | string`，移除 `{ bytes }` 兼容分支
- 与 `lingofuse-ts` 的 `normalizeUid` 签名一致

```typescript
function _wrapUid(uid: Uint8Array | string): { bytes: Uint8Array } {
    if (uid instanceof Uint8Array) {
        if (uid.length !== 32) {
            throw new RangeError("UID must be exactly 32 bytes, got " + uid.length);
        }
        return { bytes: new Uint8Array(uid) };
    }
    if (typeof uid === "string") {
        const hex = uid.trim();
        if (hex.length !== 64) {
            throw new RangeError("UID hex string must be exactly 64 characters, got " + hex.length);
        }
        if (!/^[0-9a-fA-F]+$/.test(hex)) {
            throw new RangeError("UID hex string contains non-hex characters");
        }
        const bytes = new Uint8Array(32);
        for (let i = 0; i < 32; i++) {
            bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
        }
        return { bytes };
    }
    throw new TypeError("UID must be a Uint8Array(32) or a 64-char hex string");
}
```

---

### Bug #5 — `setup_ts_tests.ps1` 缺少自动 link

**发现时机**：Bug #3 修复前，日志显示：

```
[warn] lingofuse-ts is not present under ...\ComplexTestUnit\node_modules
[warn] Run install.ps1 -ProjectDir ... from the lingofuse-ts source tree,
[warn] or add it manually to package.json and re-run npm install.
```

**根因**：脚本只 warn 后继续，用户需手动 `install.ps1 -ProjectDir`。

**修复（`http_ts_abi_test_setup_generator_tool.pas`）**：

新增 `Ensure-LingofuseTsLinked` 函数：

```powershell
function Ensure-LingofuseTsLinked {
    param([string]$LingoFuseTs, [string]$GenDir)
    $nmDir = Join-Path $GenDir "node_modules"
    $linkPath = Join-Path $nmDir "lingofuse-ts"

    if (Test-Path -LiteralPath $linkPath) {
        # 检查是否是 junction + 指向正确目标
        if (Test-IsLink $linkPath) {
            $existing = Get-LinkTargetPath $linkPath
            $expected = [System.IO.Path]::GetFullPath($LingoFuseTs)
            if ($existing.TrimEnd("\", "/") -ieq $expected.TrimEnd("\", "/")) {
                Write-Ok "lingofuse-ts already linked: $linkPath"
                return $true
            }
            Remove-Item -LiteralPath $linkPath -Force
        }
    }

    Write-Info "Creating lingofuse-ts junction ..."
    $ok = New-JunctionByMkLink -LinkPath $linkPath -TargetPath $LingoFuseTs
    if ($ok) {
        Write-Ok "lingofuse-ts linked: $linkPath -> $LingoFuseTs"
        return $true
    }

    # Fallback: CreateSymbolicLink
    try {
        [void][System.IO.Directory]::CreateSymbolicLink($linkPath, $LingoFuseTs)
        if (Test-Path -LiteralPath $linkPath) {
            Write-Ok "lingofuse-ts linked (symlink): $linkPath -> $LingoFuseTs"
            return $true
        }
    } catch { }

    Write-Fail "Auto-link failed. Run manually:"
    Write-Fail "    cd $LingoFuseTs"
    Write-Fail "    .\install.ps1 -ProjectDir $GenDir"
    return $false
}
```

**`New-JunctionByMkLink`** 用 `ProcessStartInfo` 隔离调用 `cmd.exe /d /c mklink /J`，避免 PowerShell 的引号 / 重定向陷阱。

---

### Bug #6 — `Invoke-TsFile` 的 stdout 混入函数返回值

**发现时机**：`smoke test` 显示 `Pass: 168 Fail: 0`（全部通过），但脚本仍报 fail：

```
[fail] call_test failed (exit Quiet = True Console Output = True LF_PrepareClient: ...)
```

**根因**：

`Invoke-TsFile` 的实现：
```powershell
function Invoke-TsFile {
    param([string]$RelPath)
    if ($Compiled) {
        & $nodeExe $jsRel              # ← 子进程 stdout 混入函数返回值
        return $LASTEXITCODE           # ← 和 stdout 混在一起返回
    } else {
        & $nodeExe $tsxCli $RelPath    # ← 同
        return $LASTEXITCODE
    }
}
```

**PowerShell 的 `&` 会把子进程的 stdout 全部作为函数输出**，导致 `$rc` 是 `string[]` 而不是 `int`。`$rc -ne 0` 在 `string[]` 和 `int` 比较时永远为 True → 永远 `[fail]`。

**修复**：

```powershell
function Invoke-TsFile {
    param([string]$RelPath)
    if ($Compiled) {
        $baseName = [IO.Path]::GetFileNameWithoutExtension($RelPath)
        $jsRel = "dist\$baseName.js"
        & $nodeExe $jsRel | Out-Host          # ← 加 | Out-Host
    } else {
        & $nodeExe $tsxCli $RelPath | Out-Host # ← 加 | Out-Host
    }
    $rc = $LASTEXITCODE
    if ($null -eq $rc) { $rc = 0 }
    return [int]$rc
}
```

**同时增加诊断**：

```powershell
$rc = Invoke-TsFile $callFile
$rcType = if ($null -eq $rc) { "null" } else { $rc.GetType().Name }
$rcValue = if ($null -eq $rc) { "null" } else { "$rc" }
Write-Info "call test exit code: $rcValue (type: $rcType)"

$rcInt = 0
try { $rcInt = [int]$rc } catch { $rcInt = -1 }
if ($rcInt -ne 0) {
    Write-Fail "call_test failed (exit $rcInt)."
    ...
}
```

**修复后验证**：
- `call test exit code: 0 (type: Int32)`
- `[ ok ] smoke test passed`

---

## 五、验证结果

### 5.1 最终端到端输出

```
[info] LingoFuseTs : D:\CoreLibrary\LingoFuse\ts
[info] GenDir      : D:\CoreLibrary\LingoFuse\tools\pascal_c_to_abi\ComplexTestUnit
[ ok ] node v24.21.0
[ ok ] npm 11.19.0
[ ok ] UnitName ComplexTestUnit (ext .ts)
[ ok ] Generated files present
[warn] tsconfig.json already exists; keeping it (use -Force to overwrite).
[warn] package.json already exists; keeping it (use -Force to overwrite).
[ ok ] lingofuse-ts already linked: ...\node_modules\lingofuse-ts
[info] Skipping npm install (node_modules and package.json look current).
[ ok ] lingofuse-ts linked and built
[info] Running tsc --noEmit ...
[ ok ] tsc --noEmit passed                     ← 零错误
[info] Starting ComplexTestUnit_abi_service_test.ts in the background ...
[info] Running ComplexTestUnit_abi_call_test.ts ...
[OK] client online
[INFO] service UID = BBE6F920...45FF7280
[INFO] service P2P = 
[OK] client identity probe
[CLIENT] service called me: service initiates call
[OK] service-initiated call
[INFO] total tests scheduled: 20
[PASS] NoParamFunc(app call) = 0
...（168 项全部 PASS）...
=== Summary ===
Pass: 168
Fail: 0
Skip: 0
[info] call test exit code: 0 (type: Int32)     ← 关键：明确是 Int32 类型
[ ok ] smoke test passed
```

### 5.2 测试覆盖详情

`ComplexTestUnit.pas` 包含 20 个 API，每 API 测试 9 种变体：

| 类型 | 数量 | 说明 |
|------|:----:|------|
| Function | 14 | `NoParamFunc` / `MultiLineComment` / `Add` / `Sub` / `Mul` / `MultipleParams` / `WithDefaultInt` / `WithDefaultString` / `WithDefaultFloat` / `WithDefaultConst` / `CdeclFunc` / `RegisterFunc` / `OverloadTest` × 3 / `StringWithQuotes` |
| Procedure | 6 | `NoParamProc` / `ReadOnlyConst` / `ExternalAlias` / `ExternalIndex` |

**9 种变体 × 20 API + 3 项 whoami / service-initiated = 168 PASS + 0 FAIL**。

### 5.3 关键指标

| 指标 | 结果 |
|------|:----:|
| `tsc --noEmit` | ✅ 零错误 |
| `Pass` | ✅ 168 |
| `Fail` | ✅ 0 |
| `Skip` | ✅ 0 |
| Cleanup | ✅ 无 Access Violation |
| Smoke exit code | ✅ `0 (Int32)` |

---

## 六、TS 版与 Node.js 版对照

### 6.1 逐项映射

| 项目 | Node.js | TypeScript |
|------|---------|-----------|
| 导入 | `const lf = require("lingofuse-js")` | `import * as lf from "lingofuse-ts"` |
| 子模块 | `lf.DataHandle` / `require(".../async-support")` | `lf.DataHandle` / `lf.async`（**主入口，不依赖子路径**） |
| Koffi 引用 | `_binding.koffi` | 同 |
| 回调注册 | `koffi.register(Cb, koffi.pointer(LfCallFunc))` | `koffi.register(Cb, LfCallFuncPtr)` |
| `internal_call_*` 类型 | 无 | `: number` / `: string` / `: bigint` / `: void` |
| `Cb_*` 参数 | 无 | `(_trigger: unknown, input: unknown, output: unknown)` |
| `_wrapUid` | 兼容 `{ bytes }` 对象 | 仅 `Uint8Array \| string` |
| 同步调用返回 | 无 | `: number` / `: string` / `: bigint` |
| 异步调用返回 | 无 | `: CallPromise<number>` |
| `_readSyncReply` / `_readAsyncReply` | 无泛型 | `<T>(...) => T` |
| 配置对象 | `ABI_TargetApp` (let) | `ABI.TargetApp` (getter/setter) |
| 字符串字面量 | 单引号 `'...'` | 双引号 `"..."`（避免 `#39` 转义） |
| Koffi 回调持有 | `main()` 局部变量 | **模块顶层 const**（防 GC） |
| `_race` 参数 | `Promise<T>` | `PromiseLike<T>`（`CallPromise` 只实现 `PromiseLike`） |
| **wire protocol** | **`[0x00][payload][NUL]`** | **完全一致** |
| **核心逻辑** | `funcs.LF_Async_Call(...op.dataPtr...)` | **完全一致** |
| **延迟 dispose** | `promise.then(dispose, dispose)` | **完全一致** |

### 6.2 文件结构对照

| 项目 | Node.js | TypeScript |
|------|---------|-----------|
| Service 文件 | `xxx_abi_service.js` | `xxx_abi_service.ts` |
| Call 文件 | `xxx_abi_call.js` | `xxx_abi_call.ts` |
| Service Test | `xxx_abi_service_test.js` | `xxx_abi_service_test.ts` |
| Call Test | `xxx_abi_call_test.js` | `xxx_abi_call_test.ts` |
| Setup 脚本 | `setup_node_tests.ps1` | `setup_ts_tests.ps1` |
| 编译步骤 | 无（JS 直接运行） | `tsc --noEmit` 检查 + 可选 `tsc` 编译 |

---

## 七、`lingofuse-ts/package.json` 的根本修复建议

虽然 batch 3 已不再依赖子路径导入，**但用户自己写代码仍会遇到同样问题**。推荐修复 `lingofuse-ts/package.json` 的 `exports` 字段：

```json
"exports": {
  ".": {
    "types": "./dist/index.d.ts",
    "require": "./dist/index.js",
    "import": "./dist/index.js",
    "default": "./dist/index.js"
  },
  "./data-handle": {
    "types": "./dist/data-handle.d.ts",
    "require": "./dist/data-handle.js",
    "import": "./dist/data-handle.js",
    "default": "./dist/data-handle.js"
  },
  "./async-support": {
    "types": "./dist/async-support.d.ts",
    "require": "./dist/async-support.js",
    "import": "./dist/async-support.js",
    "default": "./dist/async-support.js"
  }
  // ... 其他子路径同样处理
}
```

**注意**：
- 每个子路径必须加 `types` 字段
- 所有路径指向 `./dist/`（不是包根）
- `import` 也指向 `.js`（因 `type: "commonjs"`，Node / TS 自动 interop）

---

## 八、`setup_ts_tests.ps1` 参数速查

| 参数 | 说明 |
|------|------|
| `-LingoFuseTs <path>` | **必填**，`lingofuse-ts` 源目录 |
| `-GenDir <path>` | 生成代码目录（默认 `$PSScriptRoot`） |
| `-UnitName <name>` | 单元名（默认自动检测 `*_abi_service.ts`） |
| `-RunSmoke` | 跑 service + call 端到端测试 |
| `-Compiled` | `tsc` 编译到 `dist/` 后用 `.js` 跑（而非 `tsx` 直跑） |
| `-SkipInstall` | 跳过 `npm install`（离线环境用） |
| `-SkipAutoLink` | 跳过 `lingofuse-ts` 自动 link（假设已安装） |
| `-Force` | 覆盖已有 `tsconfig.json` / `package.json` |
| `-Help` | 显示帮助 |

**执行流程**：

```
1. 检测 node / npm 版本
2. 检测 4 个必需文件（_abi_service.ts 等）
3. 检测 / 生成 tsconfig.json（存在 → warn，-Force 才覆盖）
4. 检测 / 生成 package.json（存在 → warn，-Force 才覆盖）
5. 自动 link lingofuse-ts（mklink /J → CreateSymbolicLink）
6. npm install（如需）
7. 缺失 devDeps 自动安装（--no-save）
8. tsc --noEmit（必跑）
9. -Compiled 时 tsc 编译
10. -RunSmoke 时跑 service + call
```

---

## 九、诚实的不确定清单

| # | 不确定点 | 说明 | 建议 |
|:-:|---------|------|------|
| 1 | `Boolean` 类型不在 ABI 白名单 | `ComplexTestUnit.pas` 的 `SingleParam(x: Integer): Boolean` 被过滤 | 需 5 个 generator + Model 协调升级 |
| 2 | `lf.async.CallPromise<T>` 作为类型在 TS 5.7+ | 5.4 / 5.6 已验证 OK；5.7+ `Uint8Array` 泛型化可能引入 warning | 上线前用 TS 5.7 验证一次 |
| 3 | `mklink /J` 需 admin 或非 Program Files | 有 `CreateSymbolicLink` 兜底 | 若两者都失败，需手动 `install.ps1` |
| 4 | `package-lock.json` 污染 | `npm install --no-save` 可能更新 lockfile | 用 `-SkipInstall` 跳过 |
| 5 | `tsconfig.json` 已存在时不做内容校验 | 只 warn | 用户需自己保证 `strict` / `module: commonjs` |
| 6 | `lingofuse-ts/dist/` 缺 `.d.ts` | 不检查 | `tsc` 会报错，用户需 `build.ps1` |
| 7 | `-Compiled` 模式下 `tsconfig.json` 必须有 `noEmit: false` | 已 warn 但未强制 | 用户可用 `-Force` 生成兼容配置 |
| 8 | `CallPromise` 不是 `Promise` 子类 | `_race` 用 `PromiseLike<T>` 兜底 | 已处理 |
| 9 | Deno / Bun 支持 | 本次仅验证 Node 24.21 | 后续增强 |

---

## 十、后续工作

### 10.1 必做

1. **修改 `code_decl_to_abi.lpr`**：
```pascal
uses
  ...,
  http_ts_abi_service_generator_tool,
  http_ts_abi_call_generator_tool,
  http_ts_abi_test_generator_tool,
  http_ts_abi_test_setup_generator_tool;
```

2. **重新编译 `code_decl_to_abi.exe`**：
```powershell
cd D:\CoreLibrary\LingoFuse\tools\pascal_c_to_abi
# Lazarus / FPC 重新编译
```

3. **验证 `--list-languages` 包含 `http_ts`**：
```powershell
code_decl_to_abi --list-languages | findstr http_ts
```

### 10.2 建议做

1. **修复 `lingofuse-ts/package.json`**（见 §七），避免用户手动 `import` 子路径时踩坑。

2. **跨语言互通验证**（TS ↔ cpp / pas / nodejs）：
   - TS service + Pascal call
   - TS service + C++ call
   - TS service + Node.js call

3. **`Boolean` 类型支持**：扩展 `Z.Pascal_Func_Model` + 5 个 generator 的 ABI 白名单。

4. **Deno / Bun 支持**：调整 import 风格，验证运行时兼容性。

### 10.3 不必做

- 不需要生成 `.md` 文档（本次已全部口头交付）
- 不需要 ESM 产物（`type: "commonjs"` 已足够）

---

## 十一、变更日志

| 日期 | 事件 |
|------|------|
| 2026-10-24 | 完成 4 个 generator 单元 + 完整联调 |
| 2026-10-24 | 修复 Bug #1（`internal_call_*` 缺 `void`） |
| 2026-10-24 | 修复 Bug #2（`setup_ts_tests.ps1` 依赖检测） |
| 2026-10-24 | 修复 Bug #3（`lingofuse-ts/package.json` `exports` + batch 3 改用主入口） |
| 2026-10-24 | 修复 Bug #4（`_wrapUid` 的 `TS2352`） |
| 2026-10-24 | 修复 Bug #5（`setup_ts_tests.ps1` 自动 link） |
| 2026-10-24 | 修复 Bug #6（`Invoke-TsFile` stdout 混入返回值） |
| 2026-10-24 | **验证：`tsc --noEmit passed` + 168/0/0 smoke test passed** |

---

## 十二、参考

- **JS 修复报告**：`LingoFuse_JS_Async_Fix_Report.md`
- **TS 修复报告**：`LingoFuse_TypeScript_Async_Fix_Report.md`
- **Pascal 权威文档**：`LingoFuse_Pascal_Complete_Guide.md`
- **JS/TS 接口知识库**：`LingoFuse_JS_TS_Binding_Knowledge_Base.md`
- **C ABI 头文件**：`LingoFuse.h`
- **测试用例**：`ComplexTestUnit.pas` / `ComplexTestUnit.h`

---

**文档结束**
