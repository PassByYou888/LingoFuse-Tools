unit R_abi_test_setup_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.UnicodeMixedLib,
  Z.ListEngine,
  Z.Pascal_Func_Model,
  code_decl_to_abi_registry;

function GenerateRTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[R_abi_test_setup_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[R_abi_test_setup_generator] %s', [PFormat(Fmt, Args)]);
end;

procedure EmitHeader(Lines: TPascalStringList);
begin
  Lines.Add('#Requires -Version 5.1');
  Lines.Add('');
  Lines.Add('[CmdletBinding()]');
  Lines.Add('param(');
  Lines.Add('    [string]$RuntimeDir = "",');
  Lines.Add('    [string]$GenDir = "",');
  Lines.Add('    [string]$UnitName = "",');
  Lines.Add('    [switch]$Force,');
  Lines.Add('    [switch]$RunSmoke,');
  Lines.Add('    [switch]$Help');
  Lines.Add(')');
  Lines.Add('');
  Lines.Add('$ErrorActionPreference = "Stop"');
  Lines.Add('');
  Lines.Add('function Write-Info { param([string]$m) Write-Host "[info] $m" -ForegroundColor Cyan }');
  Lines.Add('function Write-Ok   { param([string]$m) Write-Host "[ ok ] $m" -ForegroundColor Green }');
  Lines.Add('function Write-Warn { param([string]$m) Write-Host "[warn] $m" -ForegroundColor Yellow }');
  Lines.Add('function Write-Fail { param([string]$m) Write-Host "[fail] $m" -ForegroundColor Red }');
  Lines.Add('');
end;

procedure EmitHelp(Lines: TPascalStringList);
begin
  Lines.Add('if ($Help) {');
  Lines.Add('    Write-Host "setup_R_tests.ps1"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "One-shot R ABI test environment bootstrap for LingoFuse."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Required:"');
  Lines.Add('    Write-Host "  -RuntimeDir <path>    Directory containing LingoFuse64.dll and z_ipc_64.dll."');
  Lines.Add('    Write-Host "                       Can also be provided via the LINGOFUSE_RUNTIME env var."');
  Lines.Add('    Write-Host "                       The script auto-searches common subdirectories (Binary,"');
  Lines.Add('    Write-Host "                       runtime, ..\Binary, ..\runtime, ...) if the DLL is not"');
  Lines.Add('    Write-Host "                       found directly in the given directory."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Optional:"');
  Lines.Add('    Write-Host "  -GenDir <path>        Generated project directory. Default: this script directory."');
  Lines.Add('    Write-Host "  -UnitName <name>      Source unit name. Default: auto-detect from *_abi_service_test.R."');
  Lines.Add('    Write-Host "  -Force                Rerun smoke test even if it previously succeeded."');
  Lines.Add('    Write-Host "  -RunSmoke             Start service_test.R in background, run call_test.R, verify."');
  Lines.Add('    Write-Host "  -Help                 Show this help."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Prerequisites:"');
  Lines.Add('    Write-Host "  - R for Windows installed (Rscript.exe on PATH)."');
  Lines.Add('    Write-Host "  - lingofuse R package (version 2.0+). Install with:"');
  Lines.Add('    Write-Host "        Rscript -e `"install.packages(''lingofuse'', repos=''<your-repo>'')`""');
  Lines.Add('    Write-Host "  - bit64 R package (optional; only needed for int64/uint64 parameters)."');
  Lines.Add('    Write-Host "  - The four .R files produced by code_decl_to_abi --lang r."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Exit codes: 0 = environment ready, 1 = setup or smoke failure."');
  Lines.Add('    exit 0');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitValidation(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $GenDir) { $GenDir = $PSScriptRoot }');
  Lines.Add('if (-not (Test-Path -LiteralPath $GenDir)) {');
  Lines.Add('    Write-Fail "GenDir not found: $GenDir"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$GenDir = (Resolve-Path -LiteralPath $GenDir).Path');
  Lines.Add('Write-Ok "GenDir: $GenDir"');
  Lines.Add('');
  Lines.Add('if (-not $RuntimeDir) {');
  Lines.Add('    if ($env:LINGOFUSE_RUNTIME -and (Test-Path -LiteralPath $env:LINGOFUSE_RUNTIME)) {');
  Lines.Add('        $RuntimeDir = $env:LINGOFUSE_RUNTIME');
  Lines.Add('        Write-Info "Using LINGOFUSE_RUNTIME: $RuntimeDir"');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('if (-not $RuntimeDir) {');
  Lines.Add('    Write-Fail "-RuntimeDir is required (or set the LINGOFUSE_RUNTIME env var)."');
  Lines.Add('    Write-Host "        Run setup_R_tests.ps1 -Help for usage."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('if (-not (Test-Path -LiteralPath $RuntimeDir)) {');
  Lines.Add('    Write-Fail "RuntimeDir not found: $RuntimeDir"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$RuntimeDir = (Resolve-Path -LiteralPath $RuntimeDir).Path');
  Lines.Add('');
  Lines.Add('function Test-LingoFuseDir {');
  Lines.Add('    param([string]$Dir)');
  Lines.Add('    if ([string]::IsNullOrEmpty($Dir)) { return $false }');
  Lines.Add('    if (-not (Test-Path -LiteralPath $Dir)) { return $false }');
  Lines.Add('    return (Test-Path -LiteralPath (Join-Path $Dir "LingoFuse64.dll"))');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not (Test-LingoFuseDir -Dir $RuntimeDir)) {');
  Lines.Add('    Write-Info "LingoFuse64.dll not in $RuntimeDir directly; searching common subdirectories ..."');
  Lines.Add('    $candidates = @(');
  Lines.Add('        (Join-Path $RuntimeDir "Binary"),');
  Lines.Add('        (Join-Path $RuntimeDir "runtime"),');
  Lines.Add('        (Join-Path $RuntimeDir "runtime\Binary"),');
  Lines.Add('        (Join-Path $RuntimeDir "..\Binary"),');
  Lines.Add('        (Join-Path $RuntimeDir "..\runtime"),');
  Lines.Add('        (Join-Path $RuntimeDir "..\runtime\Binary"),');
  Lines.Add('        (Join-Path $RuntimeDir "..\..\Binary"),');
  Lines.Add('        (Join-Path $RuntimeDir "..\..\runtime"),');
  Lines.Add('        (Join-Path $RuntimeDir "..\..\runtime\Binary"),');
  Lines.Add('        (Join-Path $RuntimeDir "..\..\..\Binary")');
  Lines.Add('    )');
  Lines.Add('    $found = $null');
  Lines.Add('    foreach ($c in $candidates) {');
  Lines.Add('        if (Test-LingoFuseDir -Dir $c) {');
  Lines.Add('            $found = (Resolve-Path -LiteralPath $c).Path');
  Lines.Add('            break');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('    if ($found) {');
  Lines.Add('        Write-Info "LingoFuse64.dll auto-detected at: $found"');
  Lines.Add('        $RuntimeDir = $found');
  Lines.Add('    } else {');
  Lines.Add('        Write-Fail "LingoFuse64.dll not found under: $RuntimeDir"');
  Lines.Add('        Write-Fail "        Searched the given directory and common subdirectories."');
  Lines.Add('        Write-Fail "        Pass -RuntimeDir pointing at the directory that contains LingoFuse64.dll,"');
  Lines.Add('        Write-Fail "        for example: -RuntimeDir D:\CoreLibrary\LingoFuse\Binary"');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('Write-Ok "RuntimeDir: $RuntimeDir"');
  Lines.Add('');
end;

procedure EmitToolCheck(Lines: TPascalStringList);
begin
  Lines.Add('$rscriptCmd = Get-Command Rscript.exe -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $rscriptCmd) {');
  Lines.Add('    Write-Fail "Rscript.exe not found on PATH."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$rscript = $rscriptCmd.Source');
  Lines.Add('$rVerRaw = (& $rscript "--version" 2>&1) -join " "');
  Lines.Add('Write-Ok "Rscript: $rscript"');
  Lines.Add('Write-Info "R version: $rVerRaw"');
  Lines.Add('');
  Lines.Add('Write-Info "Checking lingofuse R package ..."');
  Lines.Add('$pkgOkRaw = (& $rscript "-e" "cat(if (requireNamespace(''lingofuse'', quietly=TRUE)) ''yes'' else ''no'')" 2>&1) -join ""');
  Lines.Add('$pkgOkRaw = $pkgOkRaw.Trim()');
  Lines.Add('if ($pkgOkRaw -ne "yes") {');
  Lines.Add('    Write-Fail "lingofuse R package is not installed."');
  Lines.Add('    Write-Fail "        Install with: Rscript -e `"install.packages(''lingofuse'', repos=''<your-repo>'')`""');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$pkgVerRaw = (& $rscript "-e" "cat(as.character(packageVersion(''lingofuse'')))" 2>&1) -join ""');
  Lines.Add('$pkgVerRaw = $pkgVerRaw.Trim()');
  Lines.Add('Write-Ok "lingofuse version $pkgVerRaw (functional capability is checked below)"');
  Lines.Add('');
  Lines.Add('Write-Info "Probing lingofuse API surface (instead of requiring a specific version) ..."');
  Lines.Add('$probeR = Join-Path $env:TEMP ("lf_r_probe_" + [guid]::NewGuid().ToString("N").Substring(0,8) + ".R")');
  Lines.Add('$probeSrc = @''');
  Lines.Add('ok <- TRUE');
  Lines.Add('missing <- character(0)');
  Lines.Add('ns <- asNamespace("lingofuse")');
  Lines.Add('need <- c(');
  Lines.Add('  "lf_load", "lf_is_loaded", "lf_cleanup",');
  Lines.Add('  "lf_call_bin", "lf_uid_call_bin", "lf_p2pname_call_bin",');
  Lines.Add('  "lf_notify_bin", "lf_uid_notify_bin", "lf_p2pname_notify_bin",');
  Lines.Add('  "lf_register_call", "lf_register_notify",');
  Lines.Add('  "lf_register_p2p_call", "lf_register_p2p_notify",');
  Lines.Add('  "lf_poll", "lf_run"');
  Lines.Add(')');
  Lines.Add('for (fn in need) {');
  Lines.Add('  if (!is.function(get0(fn, envir = ns, ifnotfound = NULL))) {');
  Lines.Add('    missing <- c(missing, fn)');
  Lines.Add('    ok <- FALSE');
  Lines.Add('  }');
  Lines.Add('}');
  Lines.Add('if (!"with_context" %in% names(formals(lingofuse::lf_register_call))) {');
  Lines.Add('  missing <- c(missing, "with_context param on lf_register_call")');
  Lines.Add('  ok <- FALSE');
  Lines.Add('}');
  Lines.Add('if (!"bin" %in% names(formals(lingofuse::lf_register_call))) {');
  Lines.Add('  missing <- c(missing, "bin param on lf_register_call")');
  Lines.Add('  ok <- FALSE');
  Lines.Add('}');
  Lines.Add('if (ok) cat("OK") else cat("MISSING:", paste(missing, collapse = ", "))');
  Lines.Add('''@');
  Lines.Add('Set-Content -Path $probeR -Value $probeSrc -Encoding ASCII');
  Lines.Add('$featRaw = (& $rscript "--vanilla" $probeR 2>&1) -join ""');
  Lines.Add('Remove-Item -LiteralPath $probeR -Force -ErrorAction SilentlyContinue');
  Lines.Add('$featRaw = $featRaw.Trim()');
  Lines.Add('if ($featRaw -ne "OK") {');
  Lines.Add('    Write-Fail "lingofuse API surface is incomplete."');
  Lines.Add('    Write-Fail "        Detected: $featRaw"');
  Lines.Add('    Write-Fail "        Required functions: lf_load, lf_is_loaded, lf_cleanup,"');
  Lines.Add('    Write-Fail "            lf_call_bin, lf_uid_call_bin, lf_p2pname_call_bin,"');
  Lines.Add('    Write-Fail "            lf_notify_bin, lf_uid_notify_bin, lf_p2pname_notify_bin,"');
  Lines.Add('    Write-Fail "            lf_register_call, lf_register_notify,"');
  Lines.Add('    Write-Fail "            lf_register_p2p_call, lf_register_p2p_notify, lf_poll, lf_run"');
  Lines.Add('    Write-Fail "        Required arguments: bin and with_context on lf_register_call"');
  Lines.Add('    Write-Fail "        Your lingofuse package ($pkgVerRaw) is missing the above. Upgrade it."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "lingofuse API surface is complete."');
  Lines.Add('');
  Lines.Add('Write-Info "Checking bit64 R package (optional) ..."');
  Lines.Add('$bit64Raw = (& $rscript "-e" "cat(if (requireNamespace(''bit64'', quietly=TRUE)) ''yes'' else ''no'')" 2>&1) -join ""');
  Lines.Add('if ($bit64Raw.Trim() -eq "yes") {');
  Lines.Add('    Write-Ok "bit64 is installed (int64/uint64 supported)."');
  Lines.Add('} else {');
  Lines.Add('    Write-Warn "bit64 not installed. int64/uint64 parameters are unavailable."');
  Lines.Add('    Write-Warn "        Install with: Rscript -e `"install.packages(''bit64'')`""');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitUnitNameDetect(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    $cand = Get-ChildItem -LiteralPath $GenDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*_abi_service_test.R" } | Select-Object -First 1');
  Lines.Add('    if ($null -ne $cand) {');
  Lines.Add('        $UnitName = $cand.Name -replace "_abi_service_test\.R$", ""');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    Write-Fail "Cannot auto-detect UnitName (no *_abi_service_test.R in GenDir)."');
  Lines.Add('    Write-Fail "        Pass -UnitName explicitly."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "UnitName: $UnitName"');
  Lines.Add('');
end;

procedure EmitFileCheck(Lines: TPascalStringList);
begin
  Lines.Add('$serviceR     = Join-Path $GenDir "${UnitName}_abi_service.R"');
  Lines.Add('$callR        = Join-Path $GenDir "${UnitName}_abi_call.R"');
  Lines.Add('$serviceTestR = Join-Path $GenDir "${UnitName}_abi_service_test.R"');
  Lines.Add('$callTestR    = Join-Path $GenDir "${UnitName}_abi_call_test.R"');
  Lines.Add('');
  Lines.Add('$required = @(');
  Lines.Add('    @{ Path = $serviceR;     Role = "service module" },');
  Lines.Add('    @{ Path = $callR;        Role = "call module" },');
  Lines.Add('    @{ Path = $serviceTestR; Role = "service test program" },');
  Lines.Add('    @{ Path = $callTestR;    Role = "call test program" }');
  Lines.Add(')');
  Lines.Add('');
  Lines.Add('$missing = @()');
  Lines.Add('foreach ($r in $required) {');
  Lines.Add('    if (-not (Test-Path -LiteralPath $r.Path)) { $missing += $r.Path }');
  Lines.Add('}');
  Lines.Add('if ($missing.Count -gt 0) {');
  Lines.Add('    Write-Fail "Missing generated .R file(s):"');
  Lines.Add('    foreach ($m in $missing) { Write-Host "        $m" }');
  Lines.Add('    Write-Fail "Run code_decl_to_abi --lang r <input> <output.r> first."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "All four generated .R files present."');
  Lines.Add('');
end;

procedure EmitSmoke(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $RunSmoke) {');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Environment is ready." -ForegroundColor Green');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Run the tests manually in two terminals:" -ForegroundColor Cyan');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "  Terminal 1 (service):" -ForegroundColor Yellow');
  Lines.Add('    Write-Host "      `$env:LINGOFUSE_RUNTIME = `"$RuntimeDir`""');
  Lines.Add('    Write-Host "      cd `"$GenDir`""');
  Lines.Add('    Write-Host "      Rscript --vanilla ${UnitName}_abi_service_test.R"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "  Terminal 2 (call):" -ForegroundColor Yellow');
  Lines.Add('    Write-Host "      `$env:LINGOFUSE_RUNTIME = `"$RuntimeDir`""');
  Lines.Add('    Write-Host "      cd `"$GenDir`""');
  Lines.Add('    Write-Host "      Rscript --vanilla ${UnitName}_abi_call_test.R"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Or pass -RunSmoke to run both automatically." -ForegroundColor DarkGray');
  Lines.Add('    Write-Host ""');
  Lines.Add('    exit 0');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Write-Info "Running smoke test (service + call) ..."');
  Lines.Add('');
  Lines.Add('$env:LINGOFUSE_RUNTIME = $RuntimeDir');
  Lines.Add('if (-not $env:ABI_SERVICE_TIMEOUT) { $env:ABI_SERVICE_TIMEOUT = "30" }');
  Lines.Add('');
  Lines.Add('$svcLog = Join-Path $GenDir "service_test.log"');
  Lines.Add('$svcErr = Join-Path $GenDir "service_test.err.log"');
  Lines.Add('if (Test-Path -LiteralPath $svcLog) { Remove-Item -LiteralPath $svcLog -Force }');
  Lines.Add('if (Test-Path -LiteralPath $svcErr) { Remove-Item -LiteralPath $svcErr -Force }');
  Lines.Add('');
  Lines.Add('$svcProc = $null');
  Lines.Add('try {');
  Lines.Add('    $svcProc = Start-Process -FilePath $rscript `');
  Lines.Add('        -ArgumentList @("--vanilla", "`"$serviceTestR`"") `');
  Lines.Add('        -WorkingDirectory $GenDir `');
  Lines.Add('        -PassThru -NoNewWindow `');
  Lines.Add('        -RedirectStandardOutput $svcLog `');
  Lines.Add('        -RedirectStandardError $svcErr');
  Lines.Add('');
  Lines.Add('    Write-Info "Waiting for service [READY] (max 20s) ..."');
  Lines.Add('    $ready = $false');
  Lines.Add('    $t0 = Get-Date');
  Lines.Add('    while (((Get-Date) - $t0).TotalSeconds -lt 20) {');
  Lines.Add('        if ($svcProc -and $svcProc.HasExited) { break }');
  Lines.Add('        if (Test-Path -LiteralPath $svcLog) {');
  Lines.Add('            $c = Get-Content -LiteralPath $svcLog -Raw -ErrorAction SilentlyContinue');
  Lines.Add('            if ($c -and $c.Contains("[READY]")) { $ready = $true; break }');
  Lines.Add('        }');
  Lines.Add('        Start-Sleep -Milliseconds 200');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (-not $ready) {');
  Lines.Add('        Write-Fail "service_test.R did not reach [READY]."');
  Lines.Add('        if (Test-Path -LiteralPath $svcLog) {');
  Lines.Add('            Write-Host "--- service log ---" -ForegroundColor Yellow');
  Lines.Add('            Get-Content -LiteralPath $svcLog | ForEach-Object { Write-Host $_ }');
  Lines.Add('        }');
  Lines.Add('        if (Test-Path -LiteralPath $svcErr) {');
  Lines.Add('            Write-Host "--- service err ---" -ForegroundColor Yellow');
  Lines.Add('            Get-Content -LiteralPath $svcErr | ForEach-Object { Write-Host $_ }');
  Lines.Add('        }');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "service_test.R is ready."');
  Lines.Add('');
  Lines.Add('    Write-Info "Running call_test.R ..."');
  Lines.Add('    & $rscript "--vanilla" $callTestR');
  Lines.Add('    $callRc = $LASTEXITCODE');
  Lines.Add('');
  Lines.Add('    if ($callRc -ne 0) {');
  Lines.Add('        Write-Fail "call_test.R failed (exit $callRc)."');
  Lines.Add('        if (Test-Path -LiteralPath $svcLog) {');
  Lines.Add('            Write-Host "--- service log (tail) ---" -ForegroundColor Yellow');
  Lines.Add('            Get-Content -LiteralPath $svcLog -Tail 40 | ForEach-Object { Write-Host $_ }');
  Lines.Add('        }');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "call_test.R passed."');
  Lines.Add('');
  Lines.Add('} finally {');
  Lines.Add('    if ($svcProc -and -not $svcProc.HasExited) {');
  Lines.Add('        Write-Info "Stopping service_test.R ..."');
  Lines.Add('        try { Stop-Process -Id $svcProc.Id -Force -ErrorAction SilentlyContinue } catch {}');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Smoke test passed. Environment is ready." -ForegroundColor Green');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "For cross-language testing:" -ForegroundColor Cyan');
  Lines.Add('Write-Host "  1. Start any language service (Pascal / C++ / Node.js) on:" -ForegroundColor Yellow');
  Lines.Add('Write-Host "         ipc:${UnitName}_abi"');
  Lines.Add('Write-Host "  2. Run this R call test in a separate terminal:" -ForegroundColor Yellow');
  Lines.Add('Write-Host "         Rscript --vanilla ${UnitName}_abi_call_test.R"');
  Lines.Add('Write-Host ""');
  Lines.Add('exit 0');
  Lines.Add('');
end;

function GenerateRTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;

  Log('Generating setup_R_tests.ps1');

  Lines := TPascalStringList.Create;
  try
    EmitHeader(Lines);
    EmitHelp(Lines);
    EmitValidation(Lines);
    EmitToolCheck(Lines);
    EmitUnitNameDetect(Lines);
    EmitFileCheck(Lines);
    EmitSmoke(Lines);
    Result := Lines;
    Log(PFormat('Generated setup_R_tests.ps1 with %d lines', [Lines.Count]));
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization

  RegisterGenerator(
    'r',
    'setup_R_tests.ps1',
    gkPs1,
    'R ABI test environment setup script',
    @GenerateRTestSetupScript);

end.
