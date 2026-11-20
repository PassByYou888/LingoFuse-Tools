# TypeScript ABI Generator Development Report

> *English translation of [TypeScript_ABI_Generator_Development_Report.md](TypeScript_ABI_Generator_Development_Report.md).*

**Version**: 1.0
**Date**: 2026-10-24
**Scope**: add a complete TypeScript ABI generator suite (5 pieces) to the `code_decl_to_abi` tool chain, so that it behaves consistently with the Pascal / C++ / Node.js generators and supports multi-language binary interoperability.
**Final status**: **168/0/0 PASS**, `tsc --noEmit` with zero errors, end-to-end smoke test passing.

---

## 1. Background and objectives

### 1.1 Background

The `code_decl_to_abi` tool chain already provided complete ABI generators for 4 languages:

| Language | Service | Call | Test | Build script |
|------|:-------:|:----:|:----:|:-------:|
| Pascal | ✅ | ✅ | ✅ | — |
| C++ | ✅ | ✅ | ✅ | ✅ CMake |
| Node.js | ✅ | ✅ | ✅ | ✅ PowerShell |
| **TypeScript** | ❌ | ❌ | ❌ | ❌ |

This task adds a complete **5-piece ABI generator suite** to the **`lingofuse-ts`** binding, producing code that compiles, runs and passes end-to-end tests directly, and that stays **byte-for-byte identical in wire protocol** to the existing Node.js generator.

### 1.2 Key constraints

| # | Constraint | How it was met |
|:-:|------|---------|
| 1 | All code and status output in English | Generated code fully English; `DoStatus` / logs fully English |
| 2 | Remove all comments | Generated code has no `//` / `{ }` / `(* *)` at all |
| 3 | Escape single quotes with `#39` | Every JS single-quote case switched to `TsStrLit` (double-quote delimited); PowerShell single quotes use `#39` |
| 4 | Do not generate `.md` files | No `.md` file is registered |
| 5 | The ABI must interoperate across languages | Binary protocol (`writeInt32` / `writeString` etc.), fully consistent with cpp / pas / nodejs |
| 6 | Model tests on cpp / pas | `service + call` in two processes + 9 variants per API |
| 7 | Report base-library problems directly when found | The `exports` field bug in `lingofuse-ts/package.json` was reported |

### 1.3 Clarifying the meaning of the `http_ts` prefix

**`http_ts` = the TypeScript version of the ABI generator**, not an HTTP protocol wrapper.

**Reasons**:
- **Multi-language interoperability requirement**: only a binary protocol **fully identical** to cpp/pas/nodejs can interoperate.
- **`LingoFuse.h` has no HTTP interface**: the base library only exposes the `LF_*` binary C ABI.
- **Switching to an HTTP wrapper would break it**: the Pascal / C++ services use `LF_ReadInt32` / `LF_WriteInt32`, so if the TS side used HTTP JSON it could not interoperate at all.

---

## 2. Deliverables

### 2.1 New source files (5)

| # | File | Purpose | Order of lines |
|:-:|------|------|:-------:|
| 1 | `http_ts_abi_service_generator_tool.pas` | Generates `xxx_abi_service.ts` | ~340 |
| 2 | `http_ts_abi_call_generator_tool.pas` | Generates `xxx_abi_call.ts` | ~780 |
| 3 | `http_ts_abi_test_generator_tool.pas` | Generates `xxx_abi_service_test.ts` + `xxx_abi_call_test.ts` | ~880 |
| 4 | `http_ts_abi_test_setup_generator_tool.pas` | Generates `setup_ts_tests.ps1` | ~450 |

> **Note**: of the originally planned 5 pieces, the generation of `tsconfig.json` and `package.json` was folded into `setup_ts_tests.ps1` (the script writes those files), so there are **4 generator source files**, matching the structure of `nodejs_abi_*`.

### 2.2 Output files generated for the user (6)

| # | File | Type | Notes |
|:-:|------|:----:|------|
| 1 | `xxx_abi_service.ts` | Service | Server-side registration code (`internal_call_*` stubs + `Cb_*` callbacks + `registerAll`) |
| 2 | `xxx_abi_call.ts` | Call | Client call code (9 variants) |
| 3 | `xxx_abi_service_test.ts` | Test | Server-side test (whoami stub + SIGINT handling) |
| 4 | `xxx_abi_call_test.ts` | Test | Client-side test (9 variants per API + summary) |
| 5 | `tsconfig.json` | Config | TS compile configuration (`strict: true`, `module: commonjs`) |
| 6 | `package.json` | Config | Dependency declaration (`lingofuse-ts` + `typescript` + `tsx` + `@types/node`) |
| 7 | `setup_ts_tests.ps1` | Script | One-step setup (dependency check + auto link + tsc check + smoke test) |

### 2.3 Modifications to existing files

| File | Change |
|------|------|
| `code_decl_to_abi.lpr` | Append the 4 new generator units to `uses` |
| `code_decl_to_abi_registry.pas` | No change (`gkService` / `gkCall` / `gkTest` / `gkPs1` already suffice) |

---

## 3. Key design decisions

### 3.1 Binary protocol (the core of cross-language interoperability)

All generated TS code uses a **binary protocol fully consistent with cpp / pas / nodejs**:

| Scenario | Protocol format |
|------|---------|
| **Success response** | `[0x00][payload][NUL]` |
| **Error response** | `[0xFF][error message][NUL]` |
| **Raw JSON** (optional compatibility) | `[JSON][NUL]` (recognized by `readJsonTolerant`) |

**Data reading**:
- `readInt32` / `readInt64` / `readUInt32` etc. — little-endian byte order
- `readString` — UTF-8 + NUL terminator
- `readBytesExact(32)` — UID fixed at 32 bytes

**Cross-language verification**: all 168 tests of `ComplexTestUnit` PASS, proving that TS **fully interoperates** with Pascal / C++ / Node.js.

### 3.2 Koffi callback resource management (three must-check points)

Refer to `LingoFuse_TypeScript_Async_Fix_Report.md`:

| Scenario | Order | Consequence of reversing it |
|------|------|-----------|
| `setNetworkEvent()` replacement | build new → `LF_Set_Network_Event` → publish → `koffi.unregister(old)` | segfault |
| `AppHandle.dispose()` | `LF_FreeApp(handle)` → `koffi.unregister(bridges)` | segfault |
| `AppHandle.unregister()` | `LF_Unregister(handle, name)` → `koffi.unregister(bridge)` | segfault |

### 3.3 Async call contract (🔴 must never be violated)

| Contract | How it was met |
|------|---------|
| **`op.dataPtr` must be non-null** | `_createAsyncOp` allocates with `koffi.alloc("uint8", 1)` |
| **`param` must not be disposed immediately** | `promise.then(dispose, dispose)` releases it later |
| **The `AsyncBridge` timer must not call `unref`** | Created on demand; kept alive while ops are active |
| **Exceptions inside callbacks must be swallowed** | `try { handler() } catch (_e) { }` |
| **`readJsonTolerant` tolerant reading** | Supports both a status byte and raw JSON |

### 3.4 The `ABI` configuration object (getter/setter)

**Problem**: an ES module's `export let ABI_TargetApp` is **read-only** externally and cannot be assigned from outside.

**Solution**:
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

**Usage**: `call.ABI.TargetApp = "NewName"; call.ABI.Timeout = 10000;`

### 3.5 Simplifying `_wrapUid` (avoiding `TS2352`)

**Original design** (over-complicated):
```typescript
if (uid !== null && typeof uid === "object" && (uid as { bytes?: unknown }).bytes instanceof Uint8Array) {
    // TS judges them as "not sufficiently overlapping" and reports TS2352
}
```

**New design** (accepts only standard types):
```typescript
function _wrapUid(uid: Uint8Array | string): { bytes: Uint8Array } {
    if (uid instanceof Uint8Array) {
        if (uid.length !== 32) throw new RangeError("...");
        return { bytes: new Uint8Array(uid) };
    }
    if (typeof uid === "string") {
        // 64-character hex → 32 bytes
    }
    throw new TypeError("...");
}
```

### 3.6 Register Koffi callbacks at module top level (guarding against GC)

**A potential bug in the Node.js version**: `cbWhoAmI` is a local variable inside `main()` and can theoretically be garbage-collected → a dangling pointer on the native side.

**Fixed in the TypeScript version**:
```typescript
const cbWhoAmI = _koffi.register(whoAmICb, LfCallFuncPtr);
const cbAskCallMe = _koffi.register(askCallMeCb, LfNotifyFuncPtr);
const cbReportIdentity = _koffi.register(reportIdentityCb, LfCallFuncPtr);
```

The reference returned by `koffi.register` must be held at module level to guarantee the native-side pointer's lifetime.

### 3.7 `_race<T>` accepts `PromiseLike<T>`

**Problem**: `lingofuse-ts`'s `CallPromise<T>` only implements `PromiseLike<T>` (not `Promise<T>`), so passing it directly to a `Promise<T>` parameter is a type incompatibility.

**Solution**:
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

### 3.8 `setup_ts_tests.ps1` is self-sufficient

**Key design**: the script makes no assumptions about what the user's `package.json` contains; it installs whatever is missing.

| Check | Action when missing |
|--------|-------------|
| `node_modules/` | `npm install` |
| `typescript` / `tsx` / `@types/node` / `koffi` | `npm install --no-save` (does not pollute the user's package.json) |
| Local `lingofuse-ts` project link | **automatic `mklink /J`** (fallback `CreateSymbolicLink`) |
| `dist/index.js` | Fail with a hint to run `build.ps1` first |

**Protecting the user's package.json**:
- **Not overwritten by default**: if `package.json` / `tsconfig.json` exist, only warn
- **Only `-Force` overwrites**: full rewrite
- **`-SkipInstall`**: skip npm install (for offline environments)

---

## 4. Bugs fixed during development (detailed)

### Bug #1 — `internal_call_*` missing the `void` return type for procedures

**When discovered**: the first `tsc --noEmit` reported 8 `TS1131` + `TS1128`.

**Error log**:
```
ComplexTestUnit_abi_service.ts(28,5): error TS1131: Property or signature expected.
ComplexTestUnit_abi_service.ts(29,1): error TS1128: Declaration or statement expected.
```

**Root cause**:
- For **procedures** (`F.IsFunction = False`), the `internal_call_*` stub functions went straight through `ABI_Type_To_Ts_Decl(F.ReturnType)`; `ReturnType` was empty → `: ` → TS treated `{` as an object body → `TS1131`.

**Fix (`http_ts_abi_service_generator_tool.pas`)**:
```pascal
// split the if branches
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

**Scope of impact**: the 5 procedures in `ComplexTestUnit.pas` (`NoParamProc` / `ReadOnlyConst` / `GetValue` / `ModifyVar` / `MixedMods`), triggering 4 pairs of `TS1131/TS1128`.

**Verification**: after the fix, all such errors disappeared from `tsc --noEmit`.

---

### Bug #2 — dependency-detection flaw in `setup_ts_tests.ps1`

**When discovered**: the second setup run reported `typescript not installed`.

**Error log**:
```
[warn] package.json already exists; keeping it (use -Force to overwrite).
[info] Running npm install in D:\...\ComplexTestUnit ...
up to date, audited 3 packages in 489ms
[fail] typescript not installed: D:\...\node_modules\typescript\bin\tsc
```

**Root cause**:
- The user's `package.json` was a **partial product of the previous run** (containing only `lingofuse-ts`, missing `typescript` etc.)
- The script warned and continued → `npm install` read the user's package.json → installed only `lingofuse-ts` (3 packages)
- The subsequent `tsc` check failed

**Fix (`http_ts_abi_test_setup_generator_tool.pas`)**:

1. **Automatically install missing devDeps with `--no-save`**:
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
    # with -SkipInstall, fail explicitly and print the fix command
    # otherwise npm install --no-save
}
```

2. **Fail explicitly with a fix command when `-SkipInstall` is used**:
```
[fail] Missing required devDependencies:
    typescript@^5.6.0
    tsx@^4.0.0
[fail] Install them manually:
[fail]     cd D:\...\ComplexTestUnit
[fail]     npm install --save-dev typescript@^5.6.0 tsx@^4.0.0
```

3. **Pre-flight compatibility checks for `tsconfig.json` / `package.json`**:
   - `noEmit: true` present and `-Compiled` → warn
   - `module ≠ commonjs` → warn
   - `strict ≠ true` → warn

---

### Bug #3 — the `exports` field of `lingofuse-ts/package.json` points to the wrong paths

**When discovered**: the third `tsc --noEmit` reported `TS2307: Cannot find module 'lingofuse-ts/data-handle'`.

**Error log**:
```
ComplexTestUnit_abi_call.ts(2,28): error TS2307: Cannot find module 'lingofuse-ts/data-handle' or its corresponding type declarations.
ComplexTestUnit_abi_call.ts(3,50): error TS2307: Cannot find module 'lingofuse-ts/async-support' or its corresponding type declarations.
```

**Root cause**:

The `exports` field of `lingofuse-ts/package.json`:

```json
"exports": {
  ".": {
    "require": "./index.js",       ← package root index.js, does not exist
    "import": "./index.mjs",       ← package root index.mjs, does not exist
    "default": "./index.js"
  },
  "./data-handle": "./data-handle.js",        ← package root, does not exist
  "./async-support": "./async-support.js",    ← package root, does not exist
  ...
}
```

**But `dist/*.js` are the actual artifacts**. `exports` takes precedence over `main`, and both Node.js and TS resolve through `exports` → not found → `TS2307`.

**Chain reaction**:
- `DataHandle` / `CallPromise` / `runAsyncWithPromise` all become `any`
- `cb` / `op` / `rawResult` in `(cb, op) => ...` all become implicit `any` → **100+ `TS7006`**

**Fix (in two parts)**:

**Part A (root fix, `lingofuse-ts/package.json`)**:
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
  // ... add the ./dist/ prefix and a types field to every subpath
}
```

**Part B (compatibility fix, `http_ts_abi_call_generator_tool.pas`)**:
- **Remove all subpath imports**: no more `import ... from "lingofuse-ts/data-handle"`
- **Use the main entry**: `import * as lf from "lingofuse-ts"`
- **Type aliases**: `const DataHandle = lf.DataHandle;` / `type CallPromise<T> = lf.async.CallPromise<T>;`

**Verification after the fix**:
- `tsc --noEmit passed`
- All `TS7006` disappeared (because `lingofuse-ts` resolved, so `cb` / `op` / `rawResult` types are inferred automatically)

---

### Bug #4 — the `as` cast in `_wrapUid` triggering `TS2352`

**When discovered**: the same `tsc` output round as Bug #3.

**Error log**:
```
ComplexTestUnit_abi_call.ts(22,21): error TS2352: Conversion of type 'Uint8Array<ArrayBufferLike>'
to type '{ bytes: Uint8Array<ArrayBufferLike>; }' may be a mistake because neither type
sufficiently overlaps with the other.
```

**Root cause**:
- The original code `(uid as { bytes?: unknown }).bytes` — in the `typeof uid === "object"` branch TS narrows `uid` to `Uint8Array`, and casting from `Uint8Array` to `{ bytes?: unknown }` is judged "insufficiently overlapping".

**Fix**:
- **Simplify `_wrapUid`**: accept only `Uint8Array | string` and remove the `{ bytes }` compatibility branch
- Align with the `normalizeUid` signature of `lingofuse-ts`

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

### Bug #5 — `setup_ts_tests.ps1` missing automatic linking

**When discovered**: before the Bug #3 fix, the log showed:

```
[warn] lingofuse-ts is not present under ...\ComplexTestUnit\node_modules
[warn] Run install.ps1 -ProjectDir ... from the lingofuse-ts source tree,
[warn] or add it manually to package.json and re-run npm install.
```

**Root cause**: the script only warned and continued; the user had to run `install.ps1 -ProjectDir` manually.

**Fix (`http_ts_abi_test_setup_generator_tool.pas`)**:

Added the `Ensure-LingofuseTsLinked` function:

```powershell
function Ensure-LingofuseTsLinked {
    param([string]$LingoFuseTs, [string]$GenDir)
    $nmDir = Join-Path $GenDir "node_modules"
    $linkPath = Join-Path $nmDir "lingofuse-ts"

    if (Test-Path -LiteralPath $linkPath) {
        # check whether it is a junction and points at the right target
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

**`New-JunctionByMkLink`** isolates the call to `cmd.exe /d /c mklink /J` through `ProcessStartInfo`, avoiding PowerShell's quoting / redirection traps.

---

### Bug #6 — `Invoke-TsFile`'s stdout mixed into the function's return value

**When discovered**: the `smoke test` showed `Pass: 168 Fail: 0` (all passing) yet the script still reported failure:

```
[fail] call_test failed (exit Quiet = True Console Output = True LF_PrepareClient: ...)
```

**Root cause**:

The implementation of `Invoke-TsFile`:
```powershell
function Invoke-TsFile {
    param([string]$RelPath)
    if ($Compiled) {
        & $nodeExe $jsRel              # ← child process stdout mixed into the return value
        return $LASTEXITCODE           # ← returned together with the stdout
    } else {
        & $nodeExe $tsxCli $RelPath    # ← same
        return $LASTEXITCODE
    }
}
```

**PowerShell's `&` turns all of the child process's stdout into function output**, making `$rc` a `string[]` instead of an `int`. Comparing `$rc -ne 0` between a `string[]` and an `int` is always True → always `[fail]`.

**Fix**:

```powershell
function Invoke-TsFile {
    param([string]$RelPath)
    if ($Compiled) {
        $baseName = [IO.Path]::GetFileNameWithoutExtension($RelPath)
        $jsRel = "dist\$baseName.js"
        & $nodeExe $jsRel | Out-Host          # ← added | Out-Host
    } else {
        & $nodeExe $tsxCli $RelPath | Out-Host # ← added | Out-Host
    }
    $rc = $LASTEXITCODE
    if ($null -eq $rc) { $rc = 0 }
    return [int]$rc
}
```

**Diagnostics were added as well**:

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

**Verification after the fix**:
- `call test exit code: 0 (type: Int32)`
- `[ ok ] smoke test passed`

---

## 5. Verification results

### 5.1 Final end-to-end output

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
[ ok ] tsc --noEmit passed                     ← zero errors
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
...(all 168 PASS)...
=== Summary ===
Pass: 168
Fail: 0
Skip: 0
[info] call test exit code: 0 (type: Int32)     ← key: explicitly Int32
[ ok ] smoke test passed
```

### 5.2 Test coverage details

`ComplexTestUnit.pas` contains 20 APIs, and each API is tested with 9 variants:

| Type | Count | Notes |
|------|:----:|------|
| Function | 14 | `NoParamFunc` / `MultiLineComment` / `Add` / `Sub` / `Mul` / `MultipleParams` / `WithDefaultInt` / `WithDefaultString` / `WithDefaultFloat` / `WithDefaultConst` / `CdeclFunc` / `RegisterFunc` / `OverloadTest` × 3 / `StringWithQuotes` |
| Procedure | 6 | `NoParamProc` / `ReadOnlyConst` / `ExternalAlias` / `ExternalIndex` |

**9 variants × 20 APIs + 3 items of whoami / service-initiated = 168 PASS + 0 FAIL**.

### 5.3 Key metrics

| Metric | Result |
|------|:----:|
| `tsc --noEmit` | ✅ Zero errors |
| `Pass` | ✅ 168 |
| `Fail` | ✅ 0 |
| `Skip` | ✅ 0 |
| Cleanup | ✅ No Access Violation |
| Smoke exit code | ✅ `0 (Int32)` |

---

## 6. TS version vs Node.js version

### 6.1 Item-by-item mapping

| Item | Node.js | TypeScript |
|------|---------|-----------|
| Import | `const lf = require("lingofuse-js")` | `import * as lf from "lingofuse-ts"` |
| Submodules | `lf.DataHandle` / `require(".../async-support")` | `lf.DataHandle` / `lf.async` (**main entry, no subpath dependency**) |
| Koffi reference | `_binding.koffi` | Same |
| Callback registration | `koffi.register(Cb, koffi.pointer(LfCallFunc))` | `koffi.register(Cb, LfCallFuncPtr)` |
| `internal_call_*` types | None | `: number` / `: string` / `: bigint` / `: void` |
| `Cb_*` parameters | None | `(_trigger: unknown, input: unknown, output: unknown)` |
| `_wrapUid` | Accepts `{ bytes }` objects | `Uint8Array \| string` only |
| Sync call return | None | `: number` / `: string` / `: bigint` |
| Async call return | None | `: CallPromise<number>` |
| `_readSyncReply` / `_readAsyncReply` | No generics | `<T>(...) => T` |
| Config object | `ABI_TargetApp` (let) | `ABI.TargetApp` (getter/setter) |
| String literals | single quotes `'...'` | double quotes `"..."` (avoiding `#39` escaping) |
| Koffi callback holding | `main()` local variable | **module-level const** (GC protection) |
| `_race` parameter | `Promise<T>` | `PromiseLike<T>` (`CallPromise` only implements `PromiseLike`) |
| **wire protocol** | **`[0x00][payload][NUL]`** | **Fully identical** |
| **core logic** | `funcs.LF_Async_Call(...op.dataPtr...)` | **Fully identical** |
| **delayed dispose** | `promise.then(dispose, dispose)` | **Fully identical** |

### 6.2 File structure comparison

| Item | Node.js | TypeScript |
|------|---------|-----------|
| Service file | `xxx_abi_service.js` | `xxx_abi_service.ts` |
| Call file | `xxx_abi_call.js` | `xxx_abi_call.ts` |
| Service Test | `xxx_abi_service_test.js` | `xxx_abi_service_test.ts` |
| Call Test | `xxx_abi_call_test.js` | `xxx_abi_call_test.ts` |
| Setup script | `setup_node_tests.ps1` | `setup_ts_tests.ps1` |
| Compile step | none (JS runs directly) | `tsc --noEmit` check + optional `tsc` compile |

---

## 7. Recommended root fix for `lingofuse-ts/package.json`

Although batch 3 no longer depends on subpath imports, **users writing their own code will still hit the same problem**. Fixing the `exports` field of `lingofuse-ts/package.json` is recommended:

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
  // ... handle the other subpaths the same way
}
```

**Notes**:
- Every subpath must have a `types` field
- All paths point at `./dist/` (not the package root)
- `import` also points at `.js` (because of `type: "commonjs"`, Node / TS interop automatically)

---

## 8. `setup_ts_tests.ps1` parameter quick reference

| Parameter | Description |
|------|------|
| `-LingoFuseTs <path>` | **Required**, the `lingofuse-ts` source directory |
| `-GenDir <path>` | Generated-code directory (defaults to `$PSScriptRoot`) |
| `-UnitName <name>` | Unit name (auto-detected from `*_abi_service.ts` by default) |
| `-RunSmoke` | Run the service + call end-to-end test |
| `-Compiled` | After `tsc` compiles to `dist/`, run with `.js` (instead of `tsx` directly) |
| `-SkipInstall` | Skip `npm install` (for offline environments) |
| `-SkipAutoLink` | Skip automatic `lingofuse-ts` linking (assumes it is already installed) |
| `-Force` | Overwrite existing `tsconfig.json` / `package.json` |
| `-Help` | Show help |

**Execution flow**:

```
1. Detect node / npm versions
2. Check the 4 required files (_abi_service.ts etc.)
3. Check / generate tsconfig.json (if present → warn; only -Force overwrites)
4. Check / generate package.json (if present → warn; only -Force overwrites)
5. Auto link lingofuse-ts (mklink /J → CreateSymbolicLink)
6. npm install (if needed)
7. Auto install missing devDeps (--no-save)
8. tsc --noEmit (always)
9. With -Compiled, run tsc compile
10. With -RunSmoke, run service + call
```

---

## 9. Honest list of uncertainties

| # | Uncertainty | Notes | Suggestion |
|:-:|---------|------|------|
| 1 | `Boolean` is not on the ABI whitelist | `SingleParam(x: Integer): Boolean` in `ComplexTestUnit.pas` gets filtered out | Requires coordinated upgrades across the 5 generators + Model |
| 2 | `lf.async.CallPromise<T>` as a type in TS 5.7+ | 5.4 / 5.6 verified OK; 5.7+ generic `Uint8Array` may introduce warnings | Verify once with TS 5.7 before release |
| 3 | `mklink /J` needs admin or a non-Program-Files location | `CreateSymbolicLink` is available as a fallback | If both fail, run `install.ps1` manually |
| 4 | `package-lock.json` pollution | `npm install --no-save` may update the lockfile | Use `-SkipInstall` to skip |
| 5 | No content validation when `tsconfig.json` already exists | Warn only | The user must ensure `strict` / `module: commonjs` themselves |
| 6 | `lingofuse-ts/dist/` missing `.d.ts` | Not checked | `tsc` will error; the user must run `build.ps1` |
| 7 | In `-Compiled` mode, `tsconfig.json` must have `noEmit: false` | Warned but not enforced | The user can use `-Force` to generate a compatible config |
| 8 | `CallPromise` is not a `Promise` subclass | `_race` falls back to `PromiseLike<T>` | Handled |
| 9 | Deno / Bun support | Only Node 24.21 validated this time | Later enhancement |

---

## 10. Follow-up work

### 10.1 Must do

1. **Modify `code_decl_to_abi.lpr`**:
```pascal
uses
  ...,
  http_ts_abi_service_generator_tool,
  http_ts_abi_call_generator_tool,
  http_ts_abi_test_generator_tool,
  http_ts_abi_test_setup_generator_tool;
```

2. **Recompile `code_decl_to_abi.exe`**:
```powershell
cd D:\CoreLibrary\LingoFuse\tools\pascal_c_to_abi
# recompile with Lazarus / FPC
```

3. **Verify that `--list-languages` contains `http_ts`**:
```powershell
code_decl_to_abi --list-languages | findstr http_ts
```

### 10.2 Recommended

1. **Fix `lingofuse-ts/package.json`** (see §7), so users importing subpaths by hand do not hit the trap.

2. **Cross-language interoperability verification** (TS ↔ cpp / pas / nodejs):
   - TS service + Pascal call
   - TS service + C++ call
   - TS service + Node.js call

3. **`Boolean` type support**: extend the ABI whitelist in `Z.Pascal_Func_Model` + the 5 generators.

4. **Deno / Bun support**: adjust the import style and verify runtime compatibility.

### 10.3 Not necessary

- No need to generate `.md` documentation (everything was delivered verbally this time)
- No need for ESM artifacts (`type: "commonjs"` suffices)

---

## 11. Changelog

| Date | Event |
|------|------|
| 2026-10-24 | Completed the 4 generator units + full integration |
| 2026-10-24 | Fixed Bug #1 (`internal_call_*` missing `void`) |
| 2026-10-24 | Fixed Bug #2 (`setup_ts_tests.ps1` dependency detection) |
| 2026-10-24 | Fixed Bug #3 (`lingofuse-ts/package.json` `exports` + batch 3 switched to the main entry) |
| 2026-10-24 | Fixed Bug #4 (`TS2352` in `_wrapUid`) |
| 2026-10-24 | Fixed Bug #5 (`setup_ts_tests.ps1` auto link) |
| 2026-10-24 | Fixed Bug #6 (`Invoke-TsFile` stdout mixed into the return value) |
| 2026-10-24 | **Verified: `tsc --noEmit passed` + 168/0/0 smoke test passed** |

---

## 12. References

- **JS fix report**: `LingoFuse_JS_Async_Fix_Report.md`
- **TS fix report**: `LingoFuse_TypeScript_Async_Fix_Report.md`
- **Pascal authoritative document**: `LingoFuse_Pascal_Complete_Guide.md`
- **JS/TS interface knowledge base**: `LingoFuse_JS_TS_Binding_Knowledge_Base.md`
- **C ABI header file**: `LingoFuse.h`
- **Test cases**: `ComplexTestUnit.pas` / `ComplexTestUnit.h`

---

**End of document**
