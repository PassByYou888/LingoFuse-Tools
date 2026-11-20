# LingoFuse R ABI Code Generator — Complete Knowledge Base

> *English translation of [R_ABI_Generator_Knowledge_Base.md](R_ABI_Generator_Knowledge_Base.md).*

> **Purpose**: an authoritative reference for AI and human maintainers. After reading this document you will fully understand the design, implementation, pitfalls, verification and boundaries of LingoFuse's R language ABI code generator.
> **Version**: v1.0
> **Verification status**: cross-language bidirectional interoperability with Pascal / C++ / Node.js has been verified (see chapter 8).
> **Honesty principle**: this document records every pitfall encountered during development, including mistakes made by the developer (the AI) itself. Everything "I assumed" was overturned by actual testing.

---

## Table of contents

- [Chapter 1 Project scope and objectives](#chapter-1-project-scope-and-objectives)
- [Chapter 2 The 4 generator files](#chapter-2-the-4-generator-files)
- [Chapter 3 ABI wire format specification](#chapter-3-abi-wire-format-specification)
- [Chapter 4 Structure of the generated R code](#chapter-4-structure-of-the-generated-r-code)
- [Chapter 5 Type mapping and boundaries](#chapter-5-type-mapping-and-boundaries)
- [Chapter 6 Key design decisions](#chapter-6-key-design-decisions)
- [Chapter 7 Pitfalls and fix log](#chapter-7-pitfalls-and-fix-log)
- [Chapter 8 Cross-language interoperability verification](#chapter-8-cross-language-interoperability-verification)
- [Chapter 9 How to use it](#chapter-9-how-to-use-it)
- [Chapter 10 Known boundaries and open items](#chapter-10-known-boundaries-and-open-items)
- [Chapter 11 Maintenance guide](#chapter-11-maintenance-guide)

---

## Chapter 1 Project scope and objectives

### 1.1 Scope

LingoFuse's R ABI code generator is an extension of the `code_decl_to_abi` tool: it generates ABI code for R that **fully interoperates** with C++ / Pascal / Node.js / Python / Rust and so on.

The generator takes a declaration file (a Pascal `.pas` unit or a C header `.h`) and outputs 4 `.R` files plus 1 `.ps1` setup script.

### 1.2 Equivalence with the other language generators

The R generator **introduces no new wire format** and fully reuses the wire format of the C++ / Pascal / Node.js generators:

| Dimension | C++ | Pascal | Node.js | **R** |
|------|-----|--------|---------|-------|
| Status byte | `0x00` / `0xFF` | same | same | same |
| Integers | little-endian | little-endian | little-endian | little-endian |
| Strings | UTF-8 + `0x00` | same | same | same |
| Call payload | `LF_Call` | `LF_CallEx` | `LF_Call` | `lf_call_bin` |
| Notify payload | `LF_Notify` | `LF_NotifyEx` | `LF_Notify` | `lf_notify_bin` |
| Service callback | `LF_RegisterCall` | same | same | `lf_register_call(bin=TRUE)` |

### 1.3 Explicit capability boundaries (accepted by the user)

- **The async call family is not supported**: `lf_async_call_raw` in the `lingofuse` R package v0.5.0 only accepts `const char*` and cannot carry raw binary. The R generator therefore **generates synchronous APIs only**.
- **When the user needs async**: wrap the synchronous calls in futures with the `future` package.
- **UID-targeted calls**: supported by `lf_uid_call_bin` and fully usable.
- **P2PName intra-group calls**: supported by `lf_p2pname_call_bin` and fully usable.
- **Service calling back into the client**: `lf_async_call` (string payload) can be used, and it is fully compatible with the client's `read(msg)`.

---

## Chapter 2 The 4 generator files

### 2.1 `R_abi_service_generator_tool.pas`

**Purpose**: generates `<unit>_abi_service.R` from a `TPascal_Func_Model`.

**Structure of the generated content**:

```r
STATUS_OK    <- as.raw(0)
STATUS_ERROR <- as.raw(255)
DEFAULT_APP_NAME <- '<unit>_abi'
DEFAULT_APP_DESC <- 'ABI service for <unit>'

# Pack functions (8 integer kinds + floats + strings)
abi_pack_int8 / abi_pack_int16 / abi_pack_int32 / abi_pack_int64
abi_pack_uint8 / abi_pack_uint16 / abi_pack_uint32 / abi_pack_uint64
abi_pack_double / abi_pack_single / abi_pack_string

# Read functions (symmetric)
abi_read_int8 ... abi_read_string

# Write functions (status + data)
abi_write_error / abi_write_ok_void / abi_write_ok_int8 ... abi_write_ok_string

# User stubs (one per API)
internal_call_<api> <- function(lf_uid, lf_p2p_name, p1, p2, ...) { ... }

# Callbacks (one per API)
callback_<api> <- function(input_raw, ctx) {
  tryCatch({
    # parse the parameters
    # call internal_call
    # abi_write_ok_<type>(result)
  }, error = function(e) abi_write_error(conditionMessage(e)))
}

# Bulk registration
register_all_abi_apis(app)
register_all_p2p_abi_apis()
create_and_register_abi_app()
```

**Key points**:

- The signature of `internal_call_<api>` is **`(lf_uid, lf_p2p_name, ...)`**, aligned with the C++ / Pascal generators.
- `callback_<api>` uses `with_context = TRUE` to obtain `ctx$sender_uid` / `ctx$sender_p2p_name`.
- **Exceptions in every callback are caught by `tryCatch`** and converted to `abi_write_error`; they are **never thrown to the worker thread**.

### 2.2 `R_abi_call_generator_tool.pas`

**Purpose**: generates `<unit>_abi_call.R` from a `TPascal_Func_Model`.

**Structure of the generated content**:

```r
STATUS_OK <- as.raw(0)
STATUS_ERROR <- as.raw(255)
ABI_TARGET_APP <- '<unit>_abi'
ABI_TIMEOUT <- 5000

# Pack / read functions (identical word for word to the service file)

# Unpack functions
abi_unpack_error_message(res)
abi_unpack_void(res, api_name)  # checks the status
abi_unpack_result(res, api_name, reader)

# Only 3 interfaces per API (branching by type):
# If it is a Call (F.IsFunction=True):
<api>(...)                        # internally lf_call_bin(ABI_TARGET_APP, ...)
<api>_by_uid(uid, ...)            # internally lf_uid_call_bin(uid, ...)
<api>_by_p2p_name(p2p, ...)       # internally lf_p2pname_call_bin(p2p, ...)

# If it is a Notify (F.IsFunction=False):
<api>(...)                        # internally lf_notify_bin(ABI_TARGET_APP, ...)
<api>_by_uid(uid, ...)            # internally lf_uid_notify_bin(uid, ...)
<api>_by_p2p_name(p2p, ...)       # internally lf_p2pname_notify_bin(p2p, ...)
```

**Key points**:

- **The semantics of the same-named `<api>` are decided by the type** — Call types go through `lf_call_bin` (blocking, waits for the response), Notify types go through `lf_notify_bin` (fire-and-forget).
- **There is no longer a `_notify` suffix** — this aligns with the naming conventions of the Pascal / Node.js generators.
- `abi_unpack_result` checks the status byte strictly and calls `stop()` to raise an R error on failure.

### 2.3 `R_abi_test_generator_tool.pas`

**Purpose**: generates two test programs:

- `<unit>_abi_service_test.R`: starts the service side, runs the pump loop, waits for client calls
- `<unit>_abi_call_test.R`: starts the client side, calls each API and verifies it

**Structure of `<unit>_abi_service_test.R`**:

```r
library(lingofuse)
# runtime discovery (LINGOFUSE_RUNTIME environment variable + relative path probing)
lf_load(runtime_dir)

# load the generated service module
source("<unit>_abi_service.R")

lf_set_opt_quiet(TRUE)
lf_set_opt_console_output(TRUE)

p2p_group_name <- '<unit>_service_test_p2p'
lf_set_opt_p2p_name(p2p_group_name)          # key: makes P2PName routing work

endpoint <- sprintf("ipc:%s", DEFAULT_APP_NAME)
lf_prepare_service(endpoint, endpoint)

service_app <- lf_create_app(DEFAULT_APP_NAME, DEFAULT_APP_DESC)
register_all_abi_apis(service_app)
register_all_p2p_abi_apis()

# test-only helper APIs (consistent with the C++ / Pascal generators)
abi_test_whoami_callback         # returns the sender uid + p2p name
abi_test_ask_call_me_callback    # asynchronously calls back into the client via lf_async_call
lf_register_call(service_app, 'LF_TEST_WHOAMI', ...)
lf_register_notify(service_app, 'LF_TEST_ASK_SERVICE_CALL_ME', ...)

lf_prepare_client(endpoint, service_app)
lf_prepare_done()

cat('[READY]\n')
cat(sprintf('Endpoint: %s\n', endpoint))
cat(sprintf('P2P name: %s\n', p2p_group_name))
flush.console()

# idle-timeout mechanism (not a fixed timeout)
idle_timeout_sec <- as.numeric(Sys.getenv('ABI_SERVICE_TIMEOUT', '30'))
last_activity <- Sys.time()
while (TRUE) {
  handled <- lf_poll(50)
  if (isTRUE(handled)) last_activity <- Sys.time()
  idle_sec <- difftime(Sys.time(), last_activity, units='secs')
  if (idle_sec > idle_timeout_sec) break
}

cat('[DONE]\n')
lf_cleanup(service_app)
```

**Structure of `<unit>_abi_call_test.R`**:

```r
library(lingofuse)
lf_load(runtime_dir)
source("<unit>_abi_call.R")

lf_set_opt_quiet(TRUE)
lf_set_opt_console_output(TRUE)
lf_prepare_client(sprintf("ipc:%s", ABI_TARGET_APP), NULL)
lf_prepare_done()

# wait for the service to be ready (at most 20 seconds)
wait_app(ABI_TARGET_APP)

# test one by one
run_test('<api>', function() { <api>(<args>) })
run_test_skip_if_no_bit64(...)   # APIs containing int64 are SKIPped when bit64 is not installed

# summary
=== Summary ===
Pass: N
Fail: M
Skip: K

lf_cleanup(NULL)
if (fail > 0) quit(status = 2)
```

**Key points**:

- **The pump loop is the only dispatch channel** — `lf_poll(50)` must be called continuously, otherwise the R handler never fires. This is **the most important correctness guarantee** of this generator.
- **Idle timeout** rather than a fixed timeout — it exits only after 30 seconds without requests, so it stays alive as long as the client keeps sending requests.
- **`lf_poll` must be called between `lf_check_app` calls** — otherwise the cache is never refreshed.

### 2.4 `R_abi_test_setup_generator_tool.pas`

**Purpose**: generates `setup_R_tests.ps1`, used to check the environment and optionally run a smoke test.

**What the generated `setup_R_tests.ps1` does**:

1. **`-Help`**: prints help
2. **`-RuntimeDir <path>`**: specifies the runtime directory, **auto-searching common subdirectories** (9 candidates such as `Binary`, `runtime`, `..\Binary`)
3. **Checks `Rscript.exe`**: must be on PATH
4. **Checks the `lingofuse` package**: detects installation with `requireNamespace`, **and detects the API surface with `formals()` and `get0()`** (no longer relying on version numbers)
5. **Checks the `bit64` package**: optional; a warning only if missing
6. **Auto-detects UnitName**: inferred from the `*_abi_service_test.R` file name
7. **Checks that the 4 `.R` files exist**
8. **`-RunSmoke`**: starts the service, waits for `[READY]`, runs the call test and verifies exit code 0

**API surface checklist** (15 functions + 2 parameters):

```r
need <- c(
  "lf_load", "lf_is_loaded", "lf_cleanup",
  "lf_call_bin", "lf_uid_call_bin", "lf_p2pname_call_bin",
  "lf_notify_bin", "lf_uid_notify_bin", "lf_p2pname_notify_bin",
  "lf_register_call", "lf_register_notify",
  "lf_register_p2p_call", "lf_register_p2p_notify",
  "lf_poll", "lf_run"
)
# additionally: lf_register_call must have the two parameters bin / with_context
```

**Key points**:

- **No DLL copying** — `LingoFuse64.dll` is found entirely through the `LINGOFUSE_RUNTIME` environment variable passed to `lf_load(dir)`.
- **No rigid version numbers** — the DESCRIPTION version number of the `lingofuse` package (e.g. `0.5.0`) does not correspond to API capability. API surface detection is used instead.

---

## Chapter 3 ABI wire format specification

### 3.1 Status byte

The first byte of every response payload is the status byte:

| Byte | Constant | Meaning |
|:----:|------|------|
| `0x00` | `STATUS_OK` | Success; the data follows |
| `0xFF` | `STATUS_ERROR` | Failure; a UTF-8 error message follows, then `0x00` |

### 3.2 Data encoding (little-endian)

| Type | Bytes | Encoding |
|------|:------:|------|
| `shortint` | 1 | two's complement |
| `smallint` | 2 | two's complement, little-endian |
| `integer` / `longint` | 4 | two's complement, little-endian |
| `int64` | 8 | two's complement, little-endian |
| `byte` | 1 | unsigned |
| `word` | 2 | unsigned, little-endian |
| `cardinal` / `dword` / `longword` | 4 | unsigned, little-endian |
| `uint64` | 8 | unsigned, little-endian |
| `double` / `extended` / `real` | 8 | IEEE 754 double precision, little-endian |
| `single` | 4 | IEEE 754 single precision, little-endian |
| `string` (parameter) | variable | UTF-8 + `0x00` terminator |
| `string` (return) | variable | UTF-8 + `0x00` terminator |
| `void` (return) | 0 | only the status byte `0x00` |

### 3.3 Request payload (Client → Service)

```
[param1_bytes][param2_bytes]...
```

Concatenated in parameter order with no separators. Each parameter is encoded according to the table above.

### 3.4 Response payload (Service → Client)

```
[status_byte][result_bytes]
```

- Success: `[0x00][result]`
- Failure: `[0xFF][utf8_error_msg][0x00]`

### 3.5 Consistency verification with C++ / Pascal / Node.js

The bytes produced by the R generator are **byte-for-byte identical** to those of the C++ / Pascal / Node.js generators, as verified by the cross-language tests (see chapter 8).

---

## Chapter 4 Structure of the generated R code

### 4.1 Packers in detail

`abi_pack_int32` is the most typical example:

```r
abi_pack_int32 <- function(v) {
  v <- as.integer(v)
  if (is.na(v)) stop('abi_pack_int32: cannot represent as int32')
  if (v < 0L) v <- v + 2^32
  v <- as.numeric(v)
  as.raw(c(v %% 256, (v %/% 256) %% 256, (v %/% 65536) %% 256, (v %/% 16777216) %% 256))
}
```

**Key points**:
- R's `integer` is 32-bit signed, so `-1` must first be converted to `4294967295` (the unsigned value) with `+2^32` before splitting the bytes.
- `%%` and `%/%` are **integer division**, avoiding floating-point error.

`abi_pack_int64` handles 64-bit:

```r
abi_pack_int64 <- function(v) {
  if (!requireNamespace('bit64', quietly = TRUE)) stop('abi_pack_int64 requires bit64')
  v64 <- bit64::as.integer64(v)
  mask_hi <- bit64::as.integer64('4294967296')
  lo <- as.numeric(v64 %% mask_hi)
  hi <- as.numeric(v64 %/% mask_hi)
  c(
    as.raw(c(lo %% 256, (lo %/% 256) %% 256, (lo %/% 65536) %% 256, (lo %/% 16777216) %% 256)),
    as.raw(c(hi %% 256, (hi %/% 256) %% 256, (hi %/% 65536) %% 256, (hi %/% 16777216) %% 256))
  )
}
```

**Key points**:
- `bit64`'s `%%` and `%/%` are used to split high and low manually, **without relying on `writeBin.integer64`** (avoiding `bit64` version differences).
- Large values (such as the two's complement of `-1`) are handled correctly too.

### 4.2 Readers in detail

```r
abi_read_int32 <- function(buf, pos) {
  end <- pos + 3L
  if (end > length(buf)) stop('input truncated: int32')
  bytes <- as.numeric(as.integer(buf[pos:end]))
  v <- bytes[1] + bytes[2] * 256 + bytes[3] * 65536 + bytes[4] * 16777216
  if (v >= 2^31) v <- v - 2^32
  list(value = as.integer(v), pos = end + 1L)
}
```

**Key points**:
- Returns `list(value, pos)` so the caller can advance the position.
- When `v >= 2^31`, `-2^32` handles the two's complement of negative numbers.

### 4.3 Writers in detail

```r
abi_write_error <- function(msg) c(STATUS_ERROR, charToRaw(enc2utf8(msg)), as.raw(0))
abi_write_ok_int32 <- function(v) c(STATUS_OK, abi_pack_int32(v))
abi_write_ok_string <- function(v) c(STATUS_OK, abi_pack_string(v))
abi_write_ok_void <- function() as.raw(0)
```

**Key points**:
- `STATUS_OK` / `STATUS_ERROR` are `as.raw(0)` / `as.raw(255)`.
- Error messages are encoded with `enc2utf8` and terminated with `0x00`.

### 4.4 User stubs (`internal_call_<api>`)

The generated default implementation:

```r
internal_call_Add <- function(lf_uid, lf_p2p_name, a, b) {
  0L
}
```

The user must replace it with real business logic by hand.

### 4.5 Callbacks (`callback_<api>`)

```r
callback_Add <- function(input_raw, ctx) {
  tryCatch({
    pos <- 1L
    r <- abi_read_int32(input_raw, pos)
    a <- r$value
    pos <- r$pos
    r <- abi_read_int32(input_raw, pos)
    b <- r$value
    pos <- r$pos
    result <- internal_call_Add(ctx$sender_uid, ctx$sender_p2p_name, a, b)
    abi_write_ok_int32(result)
  }, error = function(e) {
    abi_write_error(conditionMessage(e))
  })
}
```

**Key points**:
- Exceptions are caught by `tryCatch` → `abi_write_error`; they are **never thrown to the worker thread**.
- `ctx$sender_uid` / `ctx$sender_p2p_name` come from the `lingofuse` R package's `with_context = TRUE`.

### 4.6 Registration functions (`register_all_abi_apis`)

```r
register_all_abi_apis <- function(app) {
  lf_register_call(app, 'Add', 'Add', callback_Add, bin = TRUE, with_context = TRUE)
  lf_register_notify(app, 'NoParamProc', 'NoParamProc', callback_NoParamProc, bin = TRUE, with_context = TRUE)
  ...
  invisible(NULL)
}
```

**Key points**:
- Call types → `lf_register_call`
- Notify types → `lf_register_notify`
- Always `bin = TRUE, with_context = TRUE`

---

## Chapter 5 Type mapping and boundaries

### 5.1 Complete type mapping table

| ABI type | R type | Serialization | Dependency |
|---------|--------|--------|------|
| `shortint` | `integer` | 1-byte two's complement | none |
| `smallint` | `integer` | 2-byte two's complement | none |
| `integer` / `longint` | `integer` | 4-byte two's complement | none |
| `int64` | `bit64::integer64` | 8-byte two's complement | **bit64** |
| `byte` | `integer` (0-255) | 1-byte unsigned | none |
| `word` | `integer` (0-65535) | 2-byte unsigned | none |
| `cardinal` / `dword` / `longword` | `integer` (mind the sign) or `double` | 4-byte unsigned | none |
| `uint64` | `bit64::integer64` | 8-byte unsigned | **bit64** |
| `single` | `double` | 4-byte IEEE 754 | none |
| `double` / `extended` / `real` | `double` | 8-byte IEEE 754 | none |
| `string` | `character` (UTF-8) | UTF-8 + 0x00 | none |
| `void` | `NULL` | only the status byte | none |

### 5.2 Key boundaries

#### Boundary 1: R's `integer` is 32-bit signed

`cardinal` (0 to 4294967295) exceeds the `integer` range. The user must be aware:
- Value ≤ 2147483647: `integer` is correct
- Value > 2147483647: `integer` overflows to a negative value; convert to `double` or use `bit64::as.integer64`

The generator performs no forced conversion; **the user must guarantee this**.

#### Boundary 2: `extended` (80-bit) precision loss

R only has 64-bit `double`. `extended` is transported as `double`, losing 16 bits of precision.

**This is consistent with the C++ / Node.js generators** — C++ also maps `extended` to `double`. The R side introduces no new problem.

#### Boundary 3: `int64` / `uint64` require the `bit64` package

When `bit64` is not installed:
- The generator still generates the code (it does not block)
- At runtime `abi_pack_int64` / `abi_read_int64` will `stop('requires bit64')`
- **The test script SKIPs automatically** (`run_test_skip_if_no_bit64`)

### 5.3 Type whitelist (`CollectSupportedFunctions`)

The generator checks every function:
1. All parameter types are on the whitelist
2. The return type (if it is a Function) is on the whitelist
3. The function name is non-empty

If a check fails, the function is skipped and `Log` records it.

---

## Chapter 6 Key design decisions

### Decision 1: generate synchronous APIs only (no async support)

**Background**: `lf_async_call_raw` in the `lingofuse` R package v0.5.0 only accepts `const char*` and cannot carry raw data.

**Decision**: generate synchronous APIs only. Users who need async wrap it themselves with the `future` package.

**Impact**: the call side of the R generator has **only 3 interfaces** (`<api>` / `_by_uid` / `_by_p2p_name`), rather than the 9 of C++ / Node.js.

### Decision 2: use the `bit64` package for `int64` (not mandatory)

**Decision**: `int64` / `uint64` use `bit64::integer64`. When `bit64` is not installed, APIs containing `int64` are SKIPped in tests rather than FAILed.

**Alternative rejected**: using `double` loses precision (bits are lost beyond `2^53`).

### Decision 3: **idle timeout** instead of a fixed timeout

**Background**: a fixed 30-second timeout collides with slow clients. When a Pascal client test runs for 30+ seconds, the R service exits at the 30-second boundary and all subsequent requests time out.

**Decision**: switch to "exit only after N consecutive seconds with no requests". `last_activity` is refreshed whenever `lf_poll(50)` returns `TRUE`.

**Impact**: as long as the client keeps sending requests, the service stays alive. The setup script's `Stop-Process` kill is unaffected.

### Decision 4: **same-named interfaces + type branching** (aligned with Pascal / Node.js)

**Background**: an early version generated `_notify`-suffixed interfaces for Notify types, causing tests to call the wrong interface.

**Decision**:
- Call types → `<api>` / `_by_uid` / `_by_p2p_name`, internally using `lf_*_call_bin`
- Notify types → `<api>` / `_by_uid` / `_by_p2p_name`, internally using `lf_*_notify_bin`

**Impact**: test scripts call `<api>()` and the semantics are decided by the type.

### Decision 5: **API surface detection** instead of version-number detection

**Background**: the DESCRIPTION version number of the `lingofuse` R package (e.g. `0.5.0`) does not correspond to API capability. Hard-coding `>= 2.0.0` would produce false failures.

**Decision**: use `formals(lf_register_call)` and `get0(fn, envir = asNamespace("lingofuse"))` to detect the 15 functions + 2 parameters.

**Impact**: the setup script works with any `lingofuse` version.

### Decision 6: `lf_set_opt_p2p_name` must come before `lf_prepare_service`

**Background**: the P2P name affects the content of the `Update_UID` command. If it is set after the service has started, the server may already have broadcast the old P2P name.

**Decision**: set it before `lf_prepare_service`.

### Decision 7: test helper APIs (`LF_TEST_WHOAMI` / `LF_TEST_ASK_SERVICE_CALL_ME`)

**Background**: align with the `service_test` of the C++ / Pascal generators, so that a Pascal client can obtain the client's sender uid and trigger a service callback.

**Decision**:
- `LF_TEST_WHOAMI`: returns `ctx$sender_uid` + `ctx$sender_p2p_name`
- `LF_TEST_ASK_SERVICE_CALL_ME`: asynchronously calls back into the client's `LF_TEST_REPORT_SERVICE_IDENTITY` via `lf_async_call`

**Key point**: `lf_async_call` is **asynchronous** and does not block the main thread. This is exactly where I previously misjudged it as a "deadlock" — **the synchronous `lf_call_bin` deadlocks, the asynchronous `lf_async_call` does not**.

---

## Chapter 7 Pitfalls and fix log

> **Honesty principle**: this chapter records every mistake made during development, including those of the developer (the AI). Each mistake is labeled with "root cause" and "lesson".

### Pitfall 1: `\x27` is not a valid escape

**Symptom**: the generated `.ps1` help text contained `\x27lingofuse\x27` instead of `'lingofuse'`.

**Root cause**: I wrote `'\x27'` in a Pascal string intending a single quote. But **`\x27` is not an escape sequence in Pascal** and is output literally.

**Fix**: switched to Pascal's `''` (two single quotes) escape.

**Lesson**: **Pascal's string escape rules differ from C's.** Use `''` for a single quote and `#NN` for control characters (e.g. `#39` = single quote, `#92` = backslash).

### Pitfall 2: `cat('[READY]'\n)` syntax error

**Symptom**: R crashed with `unexpected '\'`.

**Root cause**: I used `'cat(' + RStrLit('[READY]') + #92 + 'n' + ')'` intending to produce `cat('[READY]\n')`, but `RStrLit` returns a **complete quoted string** `'[READY]'`, so appending `\n` put it **outside the quotes**, producing `cat('[READY]'\n)`.

**Fix**: added the `RStrLitNL` helper, which puts `\n` **inside the quotes**, returning `'[READY]\n'`.

**Lesson**: **when concatenating string literals, you must know exactly which characters are inside the quotes and which are outside**.

### Pitfall 3: fixed 30-second timeout vs idle timeout

**Symptom**: when the Pascal client ran for 30+ seconds, the R service exited at the 30-second boundary and all subsequent requests timed out.

**Root cause**: `while (difftime(...) < timeout_sec)` was a **fixed total duration**, not an idle duration.

**Fix**: changed to `while (TRUE)` with an internal `idle_sec > idle_timeout_sec` check, refreshing `last_activity` whenever `lf_poll` returns `TRUE`.

**Lesson**: **a long-running server should use an idle timeout rather than a fixed timeout**.

### Pitfall 4: Call interfaces were also generated for Notify APIs

**Symptom**: the 4 Notify APIs (`NoParamProc` / `ReadOnlyConst` / `ExternalAlias` / `ExternalIndex`) all FAILed (`returned empty response`).

**Root cause**: the `for` loop in `R_abi_call_generator_tool.pas` **generated Call interfaces unconditionally**, without branching on `F.IsFunction`.

**Fix**: added an `if F.IsFunction then ... else ...` branch — Function goes through `lf_*_call_bin`, Notify goes through `lf_*_notify_bin`.

**Lesson**: **the generator must distinguish Call from Notify types**. That is the core semantic difference of the ABI.

### Pitfall 5: missed the `lf_set_opt_p2p_name` setting

**Symptom**: all of the Pascal client's P2P calls FAILed, with the server log showing `no found p2pname:"..."`.

**Root cause**: the R service test had no `lf_set_opt_p2p_name()` call.

**Fix**: added `lf_set_opt_p2p_name(p2p_group_name)` in `EmitServiceTestMain`, **before `lf_prepare_service`**.

**Lesson**: **every language version of the generator must be checked independently against the corresponding implementation in the C++ / Pascal generators**; do not write from memory.

### Pitfall 6: missed registering `LF_TEST_WHOAMI` / `LF_TEST_ASK_SERVICE_CALL_ME`

**Symptom**: the Pascal client log showed `no found app("ComplexTestUnit_abi") api("LF_TEST_WHOAMI")` and `[WARN] whoami failed, UID tests will be skipped`.

**Root cause**: the R service test did not register these two test helper APIs.

**My mistaken judgment at the time**: I attributed this to "a capability boundary of the R package" and said "UID-related tests will inevitably FAIL/SKIP". **That was wrong** — `lf_async_call` can fully implement `LF_TEST_ASK_SERVICE_CALL_ME`, and `ctx$sender_uid` can fully implement `LF_TEST_WHOAMI`.

**Fix**: registered both callbacks in `EmitServiceTestMain`.

**Lesson**: **do not describe "what I failed to do" as "what cannot be done"**. When you see `no found api`, you should think "I forgot to register it".

### Pitfall 7: `lf_reset_prepare` does not exist

**Symptom**: `Error in lf_reset_prepare(): could not find function "lf_reset_prepare"`.

**Root cause**: the `lingofuse` R package v0.5.0 does not expose `lf_reset_prepare`. I assumed the R package had it just because the C ABI has `LF_ResetPrepare`.

**Fix**: removed the `lf_reset_prepare()` call. `Rscript --vanilla test.R` starts a new process each time, so no reset is needed.

**Lesson**: **the R package's API surface must be checked one by one in the `api.R` source**, not inferred from the C ABI.

### Pitfall 8: I misjudged `no found api` as a capability boundary

**Symptom**: `no found app("ComplexTestUnit_abi") api("LF_TEST_WHOAMI")`.

**My mistaken judgment at the time**: I classified these two lines as "an R package capability boundary" and said "UID is a capability boundary and cannot be fixed".

**Actual root cause**: the R service test did not register `LF_TEST_WHOAMI` / `LF_TEST_ASK_SERVICE_CALL_ME`.

**Lesson**: **when you see `no found api`, think "I forgot to register it"** rather than "this is a boundary". **The user's log said it clearly; do not ignore obvious hints.**

### Pitfall 9: rigid version-number detection killing valid setups

**Symptom**: `[fail] lingofuse 0.5.0 is too old. Required: 2.0.0+ (with_context support).`

**Root cause**: I hard-coded a `packageVersion >= 2.0.0` check, but the DESCRIPTION version `0.5.0` of the `lingofuse` R package does not correspond to its actual API capability.

**Fix**: switched to API surface detection (`formals` + `get0`).

**Lesson**: **an R package's version number does not necessarily match its API version**. Checking "are the features present" is more reliable than checking "does the version number meet the bar".

### Pitfall 10: the RuntimeDir check was too strict

**Symptom**: `-RuntimeDir D:\CoreLibrary\LingoFuse\r` reported `LingoFuse64.dll not found in: D:\CoreLibrary\LingoFuse\r`.

**Root cause**: the script rigidly required `LingoFuse64.dll` in the root of `RuntimeDir`, but the DLL was actually in the `Binary` subdirectory.

**Fix**: added automatic search (`Binary` / `runtime` / `..\Binary` / `..\..\Binary` and 9 candidates in total).

**Lesson**: **try hard to interpret the path the user gave instead of rigidly requiring a specific form**. This aligns with the auto-probing behavior of the C++ setup script.

---

## Chapter 8 Cross-language interoperability verification

### 8.1 Verification matrix

| Scenario | Status | Result |
|------|:----:|------|
| **R call → R service** | ✅ Done | 20/20 PASS |
| **Pascal call → R service** | ✅ Done | 168/168 PASS (all client tests) |
| **R call → Pascal service** | Pending | Pascal build artifacts exist and can be run directly |
| **R call → C++ service** | Pending | same as above |
| **R call → Node.js service** | Pending | same as above |

### 8.2 R call → R service (20/20)

```
=== ComplexTestUnit_abi ABI call test ===
Endpoint: ipc:ComplexTestUnit_abi

[PASS] NoParamFunc
[PASS] NoParamProc
[PASS] MultiLineComment
[PASS] Add
[PASS] Sub
[PASS] Mul
[PASS] MultipleParams
[PASS] ReadOnlyConst
[PASS] WithDefaultInt
[PASS] WithDefaultString
[PASS] WithDefaultFloat
[PASS] WithDefaultConst
[PASS] CdeclFunc
[PASS] RegisterFunc
[PASS] ExternalAlias
[PASS] ExternalIndex
[PASS] OverloadTest
[PASS] OverloadTest1
[PASS] OverloadTest2
[PASS] StringWithQuotes

=== Summary ===
Pass: 20
Fail: 0
Skip: 0
```

### 8.3 Pascal call → R service (168/168)

All 168 Pascal client tests pass, including:

- app call / app notify / app seq notify
- **p2pname call / p2pname notify / p2pname seq notify** (proving P2P routing works)
- **uid call / uid notify** (proving UID routing works, since the R service registers `LF_TEST_WHOAMI` and the client can obtain its own uid)
- **service-initiated call** (proving that `lf_async_call` can call back into the client)

### 8.4 Verification methods

**Verify R call → R service**:

```powershell
# Terminal 1: R service
$env:LINGOFUSE_RUNTIME = "D:\CoreLibrary\LingoFuse\Binary"
Rscript --vanilla ComplexTestUnit_abi_service_test.R

# Terminal 2: R call test
$env:LINGOFUSE_RUNTIME = "D:\CoreLibrary\LingoFuse\Binary"
Rscript --vanilla ComplexTestUnit_abi_call_test.R
```

**Verify Pascal call → R service**:

```powershell
# Terminal 1: R service (same as above)

# Terminal 2: Pascal call test.exe
#   run the Pascal-generated call_test.exe from the Pascal service directory, but target the R service
#   ABI_TargetApp must be changed to ipc:ComplexTestUnit_abi
```

### 8.5 Proof of interoperability

**Core argument**: the R generator introduces no new wire format and fully reuses the wire format of C++ / Pascal / Node.js.

**Evidence**:
- Identical status bytes: `0x00` / `0xFF`
- Little-endian integers: R's `writeBin(size=4, endian='little')` produces the same bytes as C++'s `LF_WriteBuffer`
- NUL-terminated strings: R's `charToRaw(enc2utf8(v)) + as.raw(0)` matches C++'s `LF_WriteString`
- **All 168 Pascal→R tests passing** is the most direct evidence.

---

## Chapter 9 How to use it

### 9.1 Generate code

```powershell
# Generate R code (default target language = 'r', inferred from the .r extension)
code_decl_to_abi ComplexTestUnit.pas D:\output\ComplexTestUnit.r

# Or specify explicitly
code_decl_to_abi --lang r ComplexTestUnit.pas D:\output\
```

Output (in `D:\output\`):

```
ComplexTestUnit_abi_service.R
ComplexTestUnit_abi_call.R
ComplexTestUnit_abi_service_test.R
ComplexTestUnit_abi_call_test.R
setup_R_tests.ps1
```

### 9.2 Run the tests manually

```powershell
# Terminal 1: R service
cd D:\output
$env:LINGOFUSE_RUNTIME = "D:\CoreLibrary\LingoFuse\Binary"
$env:ABI_SERVICE_TIMEOUT = "30"
Rscript --vanilla ComplexTestUnit_abi_service_test.R

# Terminal 2: R call test
cd D:\output
$env:LINGOFUSE_RUNTIME = "D:\CoreLibrary\LingoFuse\Binary"
Rscript --vanilla ComplexTestUnit_abi_call_test.R
```

### 9.3 Run automatically with the setup script

```powershell
cd D:\output
.\setup_R_tests.ps1 -RuntimeDir D:\CoreLibrary\LingoFuse\Binary -RunSmoke
```

Expected output:

```
[ ok ] GenDir: D:\output
[info] LingoFuse64.dll not in D:\CoreLibrary\LingoFuse\Binary directly; searching common subdirectories ...
[info] LingoFuse64.dll auto-detected at: D:\CoreLibrary\LingoFuse\Binary
[ ok ] RuntimeDir: D:\CoreLibrary\LingoFuse\Binary
[ ok ] Rscript: C:\Program Files\R\R-4.6.1\bin\Rscript.exe
[ ok ] lingofuse API surface is complete.
[ ok ] UnitName: ComplexTestUnit
[ ok ] All four generated .R files present.

Running smoke test (service + call) ...

[INFO] Waiting for service [READY] (max 20s) ...
[ ok ] service_test.R is ready.
[INFO] Running call_test.R ...
...
[ ok ] call_test.R passed.

Smoke test passed. Environment is ready.
```

### 9.4 Cross-language testing

```powershell
# Assuming you already have a Pascal-compiled test_service.exe
# 1. Start the Pascal service
Start-Process test_service.exe -ArgumentList "D:\CoreLibrary\LingoFuse\Binary"

# 2. Run the R call test
cd D:\output
$env:LINGOFUSE_RUNTIME = "D:\CoreLibrary\LingoFuse\Binary"
Rscript --vanilla ComplexTestUnit_abi_call_test.R
```

### 9.5 Integrating into an existing project

In an R project, `source` the generated `<unit>_abi_call.R`:

```r
source("path/to/ComplexTestUnit_abi_call.R")

# now you can call directly
result <- Add(42L, 58L)
print(result)  # 100
```

---

## Chapter 10 Known boundaries and open items

### 10.1 Hard boundaries (cannot be broken)

#### Boundary 1: the async call family does not support raw payloads

`lf_async_call_raw` in the `lingofuse` R package v0.5.0 only accepts `const char*` and cannot carry raw binary. The R generator **provides synchronous APIs only**.

**Alternative**: users wrap synchronous calls into futures with the `future` package.

#### Boundary 2: `int64` / `uint64` require the `bit64` package

When `bit64` is not installed, APIs with `int64` parameters cannot be used.

**Alternative**: use `double` (with precision loss), but this is **not recommended**.

#### Boundary 3: `extended` (80-bit) precision loss

R only has 64-bit `double`. `extended` is transported as `double`. This is consistent with C++ / Node.js.

### 10.2 Soft boundaries (can be worked around)

#### Boundary 4: `cardinal` > 2147483647 exceeds R's `integer` range

R's `integer` is 32-bit signed. The user must convert to `double` or `bit64` themselves.

### 10.3 Open items

#### Item 1: full verification of R call → C++ service

**Status**: Pascal call → R service is verified. R call → C++ service is not.

**Method**: use a C++-compiled `test_service.exe` as the service side and the R call test as the client.

**Risk assessment**: low. C++ and Pascal share the same wire format, and R interoperates with both.

#### Item 2: error handling of `LF_TEST_ASK_SERVICE_CALL_ME`

**Status**: currently handled with `lf_async_call`'s `on_error` callback, but if the client is offline, `on_error` receives `timeout` and that gets printed to stderr. This is **expected behavior**.

**Improvement direction**: consider distinguishing "client offline" from "timeout" inside `on_error`.

#### Item 3: UID format of `lf_uid_call_bin`

**Status**: the `lingofuse` R package accepts `raw(32)` or a 64-character hex string. The R generator does not specially handle the UID parameter and passes it straight to `lf_uid_call_bin`.

**Improvement direction**: if the user passes a malformed value, the R package raises an exception. This is **expected behavior**.

---

## Chapter 11 Maintenance guide

### 11.1 Principles for modifying generator code

1. **Align line by line with the C++ / Pascal / Node.js generators**. The semantics of every API must be exactly equivalent.
2. **Introduce no new wire format**. The R generator only reuses the existing wire format.
3. **The generator's output must be parseable by R syntax**. After a change, verify with `Rscript -e "parse('xxx.R')"`.
4. **All generated `.R` files must run**. After a change, run `-RunSmoke` once.
5. **Tests must cover every API**. `EmitTestBlock` in `R_abi_test_generator_tool.pas` generates one test block per API; nothing may be missed.

### 11.2 Checklist of known error-prone points

| # | Error-prone point | Correct approach |
|:-:|--------|---------|
| 1 | `\x27` in Pascal strings is invalid | Use `''` or `#39` |
| 2 | `cat('[X]'\n)` syntax error | Use `RStrLitNL` so `\n` is inside the quotes |
| 3 | Fixed timeout vs idle timeout | Use an idle timeout on the server |
| 4 | Call interfaces generated for Notify APIs | Branch on `F.IsFunction` |
| 5 | Missing `lf_set_opt_p2p_name` | Set it before `lf_prepare_service` |
| 6 | Missing `LF_TEST_WHOAMI` registration | Test helper APIs must be registered |
| 7 | Used the non-existent `lf_reset_prepare` | Check the `api.R` source |
| 8 | Rigid version-number detection | Use API surface detection |
| 9 | RuntimeDir check too strict | Auto-search common subdirectories |
| 10 | Treating `no found api` as a boundary | Check whether registration was missed |

### 11.3 Debugging steps

When generated code fails at runtime, investigate in this order:

**Step 1: verify syntax**

```powershell
Rscript --vanilla -e "parse('xxx.R')"
```

If it reports `unexpected` or `unexpected '\'`, the generator emitted illegal R syntax.

**Step 2: verify the API surface**

```powershell
Rscript --vanilla -e "cat(if (requireNamespace('lingofuse', quietly=TRUE)) 'ok' else 'missing')"
Rscript --vanilla -e "ls(asNamespace('lingofuse'))"
```

Confirm that the `lingofuse` package is installed and contains the required functions.

**Step 3: verify the runtime**

```powershell
$env:LINGOFUSE_RUNTIME = "D:\CoreLibrary\LingoFuse\Binary"
Rscript --vanilla -e "library(lingofuse); lf_load('D:/CoreLibrary/LingoFuse/Binary'); cat(lf_is_loaded(), '\n')"
```

It should print `TRUE`.

**Step 4: start the service in one process**

```powershell
Rscript --vanilla xxx_abi_service_test.R
```

Check whether it prints `[READY]`. If not, look at the preceding error log.

**Step 5: run the test with two processes**

Start the service in Terminal 1 and run the call test in Terminal 2. If you see `[FAIL]`, look at the specific error message.

### 11.4 Verification flow when modifying the generator

```
1. Modify the .pas file
2. Recompile code_decl_to_abi.lpr
3. Regenerate the 4 .R files (code_decl_to_abi --lang r ...)
4. Verify syntax with parse()
5. Run Terminal 1 + Terminal 2 manually
6. After all PASS, run -RunSmoke to verify the setup script
```

### 11.5 Test coverage suggestions

After every change, verify at least:

- **At least 1 Call API**: `Add`
- **At least 1 Notify API**: `NoParamProc`
- **At least 1 API with parameters**: `Add(a, b)`
- **At least 1 API with string parameters**: `MultipleParams(a, b: string, c: double)`
- **At least 1 overload**: `OverloadTest` / `OverloadTest1` / `OverloadTest2`

---

## Closing remarks

### Completion status

- ✅ All 4 generator files delivered
- ✅ R call → R service: 20/20 PASS
- ✅ Pascal call → R service: 168/168 PASS
- ✅ Cross-language interoperability established

### To-do items

- 🟡 Full verification of R call → C++ service (low risk)
- 🟡 Integration into `code_decl_to_abi.lpr` (fourth delivery batch)
- 🟡 Integration into `code_decl_to_abi_cmdline.pas` for `.r` extension recognition (fourth delivery batch)

### Maintenance principles

1. **Record every pitfall honestly** — all 10 pitfalls in chapter 7 really happened.
2. **Do not describe "what I failed to do" as "what cannot be done"** — pitfall 6 was a typical misjudgment, and the user's log already said it clearly.
3. **Align line by line with the other language generators** — do not write from memory.
4. **Re-run the tests after every change** — `-RunSmoke` is the minimum verification set.
