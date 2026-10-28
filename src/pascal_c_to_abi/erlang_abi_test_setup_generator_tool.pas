unit erlang_abi_test_setup_generator_tool;

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

function GenerateErlangTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[erlang_abi_test_setup_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[erlang_abi_test_setup_generator] %s', [PFormat(Fmt, Args)]);
end;

function MakeApiName(const FuncName: TP_String): SystemString;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_').Text;
end;

procedure EmitHeader(Lines: TPascalStringList);
begin
  Lines.Add('#Requires -Version 5.1');
  Lines.Add('[CmdletBinding()]');
  Lines.Add('param(');
  Lines.Add('    [string]$LingofuseEbin = "",');
  Lines.Add('    [string]$GenDir = "",');
  Lines.Add('    [string]$UnitName = "",');
  Lines.Add('    [switch]$Force,');
  Lines.Add('    [switch]$RunSmoke,');
  Lines.Add('    [switch]$Clean,');
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
  Lines.Add('function Write-TextFileNoBom {');
  Lines.Add('    param([string]$Path, [string]$Content)');
  Lines.Add('    $utf8NoBom = New-Object System.Text.UTF8Encoding $false');
  Lines.Add('    [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitHelp(Lines: TPascalStringList);
begin
  Lines.Add('if ($Help) {');
  Lines.Add('    Write-Host "setup_erlang_tests.ps1"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Required:"');
  Lines.Add('    Write-Host "  -LingofuseEbin <path>   directory containing lingofuse.beam"');
  Lines.Add('    Write-Host "Optional:"');
  Lines.Add('    Write-Host "  -GenDir <path>          default: script directory"');
  Lines.Add('    Write-Host "  -UnitName <name>        default: auto-detect from *_abi_service.erl"');
  Lines.Add('    Write-Host "  -Force                  overwrite existing files in src/"');
  Lines.Add('    Write-Host "  -Clean                  delete _build/ and ebin/ before compiling"');
  Lines.Add('    Write-Host "  -RunSmoke               start service + call for end-to-end validation"');
  Lines.Add('    Write-Host "  -Help                   show this help"');
  Lines.Add('    exit 0');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitEbinResolver(Lines: TPascalStringList);
begin
  Lines.Add('function Resolve-LingofuseEbin {');
  Lines.Add('    param([string]$InputPath)');
  Lines.Add('    if ([string]::IsNullOrWhiteSpace($InputPath)) { throw "empty path" }');
  Lines.Add('    if (-not (Test-Path -LiteralPath $InputPath)) { throw "not found: $InputPath" }');
  Lines.Add('    $p = (Resolve-Path -LiteralPath $InputPath).Path');
  Lines.Add('    if (Test-Path -LiteralPath (Join-Path $p "lingofuse.beam")) { return $p }');
  Lines.Add('    $a = Join-Path $p "lingofuse\ebin"');
  Lines.Add('    if (Test-Path -LiteralPath (Join-Path $a "lingofuse.beam")) { return $a }');
  Lines.Add('    $b = Join-Path $p "_build\default\lib\lingofuse\ebin"');
  Lines.Add('    if (Test-Path -LiteralPath (Join-Path $b "lingofuse.beam")) { return $b }');
  Lines.Add('    $c = Join-Path $p "_build\test\lib\lingofuse\ebin"');
  Lines.Add('    if (Test-Path -LiteralPath (Join-Path $c "lingofuse.beam")) { return $c }');
  Lines.Add('    $d = Join-Path $p "ebin"');
  Lines.Add('    if (Test-Path -LiteralPath (Join-Path $d "lingofuse.beam")) { return $d }');
  Lines.Add('    throw "cannot locate lingofuse.beam under: $p"');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitFindRebar3(Lines: TPascalStringList);
begin
  Lines.Add('function Find-Rebar3 {');
  Lines.Add('    param([string[]]$SearchRoots)');
  Lines.Add('    $names = @("rebar3.cmd", "rebar3.bat", "rebar3.exe", "rebar3")');
  Lines.Add('    foreach ($n in $names) {');
  Lines.Add('        $cmd = Get-Command $n -ErrorAction SilentlyContinue');
  Lines.Add('        if ($null -ne $cmd) { return $cmd.Source }');
  Lines.Add('    }');
  Lines.Add('    foreach ($root in $SearchRoots) {');
  Lines.Add('        if ([string]::IsNullOrWhiteSpace($root)) { continue }');
  Lines.Add('        if (-not (Test-Path -LiteralPath $root)) { continue }');
  Lines.Add('        $p = (Resolve-Path -LiteralPath $root).Path');
  Lines.Add('        for ($i = 0; $i -lt 12; $i++) {');
  Lines.Add('            if ([string]::IsNullOrEmpty($p)) { break }');
  Lines.Add('            foreach ($n in $names) {');
  Lines.Add('                $c = Join-Path $p $n');
  Lines.Add('                if (Test-Path -LiteralPath $c) { return $c }');
  Lines.Add('            }');
  Lines.Add('            $parent = Split-Path -Parent $p');
  Lines.Add('            if ([string]::IsNullOrEmpty($parent) -or $parent -eq $p) { break }');
  Lines.Add('            $p = $parent');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('    return $null');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitResolveEbin(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $LingofuseEbin) {');
  Lines.Add('    Write-Fail "-LingofuseEbin is required."');
  Lines.Add('    Write-Host "        Run setup_erlang_tests.ps1 -Help for usage."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('try {');
  Lines.Add('    $resolvedEbin = Resolve-LingofuseEbin -InputPath $LingofuseEbin');
  Lines.Add('} catch {');
  Lines.Add('    Write-Fail "Cannot resolve -LingofuseEbin: $($_.Exception.Message)"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$LingofuseEbin = $resolvedEbin');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath (Join-Path $LingofuseEbin "lingofuse.beam"))) {');
  Lines.Add('    Write-Fail "resolved ebin has no lingofuse.beam: $LingofuseEbin"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $GenDir) { $GenDir = $PSScriptRoot }');
  Lines.Add('$GenDir = (Resolve-Path -LiteralPath $GenDir).Path');
  Lines.Add('Write-Info "Lingofuse ebin : $LingofuseEbin"');
  Lines.Add('Write-Info "GenDir         : $GenDir"');
  Lines.Add('');
end;

procedure EmitToolCheck(Lines: TPascalStringList);
begin
  Lines.Add('$erlCmd = Get-Command erl -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $erlCmd) {');
  Lines.Add('    Write-Fail "erl is not on PATH."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$erlExe = $erlCmd.Source');
  Lines.Add('Write-Ok "erl $erlExe"');
  Lines.Add('');
  Lines.Add('$erlcCmd = Get-Command erlc -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $erlcCmd) {');
  Lines.Add('    Write-Fail "erlc is not on PATH."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "erlc $($erlcCmd.Source)"');
  Lines.Add('');
  Lines.Add('$escriptCmd = Get-Command escript -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $escriptCmd) {');
  Lines.Add('    Write-Fail "escript is not on PATH."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "escript $($escriptCmd.Source)"');
  Lines.Add('');
  Lines.Add('$otpRaw = (& $erlExe -noshell -eval "io:put_chars(erlang:system_info(otp_release)), halt()." 2>&1) -join ""');
  Lines.Add('$otpRelease = $otpRaw.Trim()');
  Lines.Add('if ((-not $otpRelease) -or ($otpRelease -notmatch "^[0-9]")) {');
  Lines.Add('    Write-Fail "Cannot determine OTP release from erl."');
  Lines.Add('    if ($otpRelease) { Write-Host ("        raw output: " + $otpRelease) -ForegroundColor Red }');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "OTP release $otpRelease"');
  Lines.Add('$otpInt = 0');
  Lines.Add('if ($otpRelease -match "^([0-9]+)") { $otpInt = [int]$matches[1] }');
  Lines.Add('if ($otpInt -lt 27) {');
  Lines.Add('    Write-Fail "OTP $otpRelease is too old; need OTP 27+"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "OTP version check passed."');
  Lines.Add('');
end;

procedure EmitUnitNameDetect(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    $found = ""');
  Lines.Add('    $cands = @(Get-ChildItem -LiteralPath $GenDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*_abi_service.erl" })');
  Lines.Add('    foreach ($c in $cands) {');
  Lines.Add('        $n = [string]$c.Name');
  Lines.Add('        if ($n.EndsWith("_abi_service.erl")) {');
  Lines.Add('            $found = $n.Substring(0, $n.Length - 16)');
  Lines.Add('            break');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('    if ($found) { $UnitName = $found }');
  Lines.Add('}');
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    $found = ""');
  Lines.Add('    $cands = @(Get-ChildItem -LiteralPath $GenDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*_abi.app.src" })');
  Lines.Add('    foreach ($c in $cands) {');
  Lines.Add('        $n = [string]$c.Name');
  Lines.Add('        if ($n.EndsWith("_abi.app.src")) {');
  Lines.Add('            $found = $n.Substring(0, $n.Length - 12)');
  Lines.Add('            break');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('    if ($found) { $UnitName = $found }');
  Lines.Add('}');
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    Write-Fail "Cannot auto-detect UnitName. Pass -UnitName explicitly."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if ($UnitName -match ''[\\/:*?"<>|]'') {');
  Lines.Add('    Write-Fail "Auto-detected UnitName contains illegal characters: ''$UnitName''. Pass -UnitName explicitly."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('if ($UnitName.EndsWith(".app.src") -or $UnitName.EndsWith(".erl") -or $UnitName.EndsWith(".beam")) {');
  Lines.Add('    Write-Fail "Auto-detected UnitName looks like a file name: ''$UnitName''. Pass -UnitName explicitly."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Info "UnitName       : $UnitName"');
  Lines.Add('');
end;

procedure EmitCleanupStale(Lines: TPascalStringList);
begin
  Lines.Add('$stalePatterns = @(');
  Lines.Add('    "*_abi.app.src_abi.app.src",');
  Lines.Add('    "*_abi.app.src_abi_service.erl",');
  Lines.Add('    "*_abi.app.src_abi_call.erl",');
  Lines.Add('    "*_abi.app.src_abi_service_main.erl",');
  Lines.Add('    "*_abi.app.src_abi_call_main.erl"');
  Lines.Add(')');
  Lines.Add('$srcDirForCleanup = Join-Path $GenDir "src"');
  Lines.Add('if (Test-Path -LiteralPath $srcDirForCleanup) {');
  Lines.Add('    foreach ($pat in $stalePatterns) {');
  Lines.Add('        $badFiles = @(Get-ChildItem -LiteralPath $srcDirForCleanup -Filter $pat -File -ErrorAction SilentlyContinue)');
  Lines.Add('        foreach ($bf in $badFiles) {');
  Lines.Add('            Write-Warn "removing stale bad-name file: $($bf.FullName)"');
  Lines.Add('            Remove-Item -LiteralPath $bf.FullName -Force -ErrorAction SilentlyContinue');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitLayout(Lines: TPascalStringList);
begin
  Lines.Add('$srcDir = Join-Path $GenDir "src"');
  Lines.Add('if (-not (Test-Path -LiteralPath $srcDir)) {');
  Lines.Add('    New-Item -ItemType Directory -Path $srcDir | Out-Null');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$patterns = @("_abi_service.erl", "_abi_call.erl", "_abi_service_main.erl", "_abi_call_main.erl")');
  Lines.Add('foreach ($pat in $patterns) {');
  Lines.Add('    $rootFiles = @(Get-ChildItem -LiteralPath $GenDir -File -Filter ("*" + $pat) -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -eq $GenDir })');
  Lines.Add('    foreach ($rf in $rootFiles) {');
  Lines.Add('        $dst = Join-Path $srcDir $rf.Name');
  Lines.Add('        $doMove = $true');
  Lines.Add('        if (Test-Path -LiteralPath $dst) {');
  Lines.Add('            if ($Force) {');
  Lines.Add('                Write-Info ("  " + $rf.Name + " -> src/ (forced)")');
  Lines.Add('            } elseif ($rf.LastWriteTime -gt (Get-Item -LiteralPath $dst).LastWriteTime) {');
  Lines.Add('                Write-Info ("  " + $rf.Name + " -> src/ (newer)")');
  Lines.Add('            } else {');
  Lines.Add('                Write-Info ("  " + $rf.Name + " already up to date in src/, skip")');
  Lines.Add('                $doMove = $false');
  Lines.Add('            }');
  Lines.Add('        } else {');
  Lines.Add('            Write-Info ("  " + $rf.Name + " -> src/")');
  Lines.Add('        }');
  Lines.Add('        if ($doMove) {');
  Lines.Add('            Move-Item -LiteralPath $rf.FullName -Destination $dst -Force');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitScaffold(Lines: TPascalStringList);
begin
  Lines.Add('$rebarConfig = Join-Path $GenDir "rebar.config"');
  Lines.Add('if ((-not (Test-Path -LiteralPath $rebarConfig)) -or $Force) {');
  Lines.Add('    $rebarContent = @"');
  Lines.Add('{erl_opts, [debug_info,');
  Lines.Add('            warn_export_vars,');
  Lines.Add('            warn_shadow_vars,');
  Lines.Add('            warn_unused_import,');
  Lines.Add('            warn_unused_vars,');
  Lines.Add('            warn_unused_function,');
  Lines.Add('            warn_deprecated_function,');
  Lines.Add('            warn_deprecated_type]}.');
  Lines.Add('');
  Lines.Add('{deps, []}.');
  Lines.Add('');
  Lines.Add('{shell, [{apps, [' + #39 + '${UnitName}_abi' + #39 + ']}]}.');
  Lines.Add('"@');
  Lines.Add('    Write-TextFileNoBom -Path $rebarConfig -Content $rebarContent');
  Lines.Add('    Write-Info "wrote rebar.config"');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$appSrcPath = Join-Path $srcDir ("${UnitName}_abi.app.src")');
  Lines.Add('if ((-not (Test-Path -LiteralPath $appSrcPath)) -or $Force) {');
  Lines.Add('    $appSrcContent = @"');
  Lines.Add('{application, ' + #39 + '${UnitName}_abi' + #39 + ',');
  Lines.Add(' [{description, "ABI service for ${UnitName}"},');
  Lines.Add('  {vsn, "0.1.0"},');
  Lines.Add('  {registered, []},');
  Lines.Add('  {applications, [kernel, stdlib]},');
  Lines.Add('  {env, []},');
  Lines.Add('  {modules, []}]}.');
  Lines.Add('"@');
  Lines.Add('    Write-TextFileNoBom -Path $appSrcPath -Content $appSrcContent');
  Lines.Add('    Write-Info "wrote src/${UnitName}_abi.app.src"');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSanityCheck(Lines: TPascalStringList);
begin
  Lines.Add('$erlFiles = @(');
  Lines.Add('    "src/${UnitName}_abi_service.erl",');
  Lines.Add('    "src/${UnitName}_abi_call.erl",');
  Lines.Add('    "src/${UnitName}_abi_service_main.erl",');
  Lines.Add('    "src/${UnitName}_abi_call_main.erl"');
  Lines.Add(')');
  Lines.Add('$stale = @()');
  Lines.Add('foreach ($rel in $erlFiles) {');
  Lines.Add('    $p = Join-Path $GenDir $rel');
  Lines.Add('    if (-not (Test-Path -LiteralPath $p)) { continue }');
  Lines.Add('    $c = Get-Content -LiteralPath $p -Raw');
  Lines.Add('    if ($null -eq $c) { $stale += $rel; continue }');
  Lines.Add('    $firstLine = ($c -split "`n")[0]');
  Lines.Add('    if ($null -eq $firstLine -or -not $firstLine.TrimStart().StartsWith(''-module('')) { $stale += $rel }');
  Lines.Add('}');
  Lines.Add('if ($stale.Count -gt 0) {');
  Lines.Add('    Write-Fail "Stale .erl files without -module() declaration:"');
  Lines.Add('    foreach ($s in $stale) { Write-Host "        $s" }');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "Sanity check passed."');
  Lines.Add('');
end;

procedure EmitFileCheck(Lines: TPascalStringList);
begin
  Lines.Add('$required = @(');
  Lines.Add('    "rebar.config",');
  Lines.Add('    "src/${UnitName}_abi.app.src",');
  Lines.Add('    "src/${UnitName}_abi_service.erl",');
  Lines.Add('    "src/${UnitName}_abi_call.erl",');
  Lines.Add('    "src/${UnitName}_abi_service_main.erl",');
  Lines.Add('    "src/${UnitName}_abi_call_main.erl"');
  Lines.Add(')');
  Lines.Add('$missing = @()');
  Lines.Add('foreach ($rel in $required) {');
  Lines.Add('    if (-not (Test-Path -LiteralPath (Join-Path $GenDir $rel))) { $missing += $rel }');
  Lines.Add('}');
  Lines.Add('if ($missing.Count -gt 0) {');
  Lines.Add('    Write-Fail "Missing files:"');
  Lines.Add('    foreach ($m in $missing) { Write-Host "        $m" }');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "All required files present."');
  Lines.Add('');
end;

procedure EmitBuild(Lines: TPascalStringList);
begin
  Lines.Add('if ($Clean) {');
  Lines.Add('    $buildDir = Join-Path $GenDir "_build"');
  Lines.Add('    if (Test-Path -LiteralPath $buildDir) {');
  Lines.Add('        Remove-Item -LiteralPath $buildDir -Recurse -Force -ErrorAction SilentlyContinue');
  Lines.Add('        Write-Info "cleaned _build/"');
  Lines.Add('    }');
  Lines.Add('    $ebinCleanDir = Join-Path $GenDir "ebin"');
  Lines.Add('    if (Test-Path -LiteralPath $ebinCleanDir) {');
  Lines.Add('        Remove-Item -LiteralPath $ebinCleanDir -Recurse -Force -ErrorAction SilentlyContinue');
  Lines.Add('        Write-Info "cleaned ebin/"');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$ebinDir = ""');
  Lines.Add('$rebar3Exe = Find-Rebar3 -SearchRoots @($GenDir, $LingofuseEbin)');
  Lines.Add('if ($null -ne $rebar3Exe) {');
  Lines.Add('    Write-Info "Build backend: rebar3 ($rebar3Exe)"');
  Lines.Add('    Push-Location $GenDir');
  Lines.Add('    $rc = 0');
  Lines.Add('    try {');
  Lines.Add('        $ext = [IO.Path]::GetExtension($rebar3Exe)');
  Lines.Add('        if ($ext -ieq ".cmd" -or $ext -ieq ".bat" -or $ext -ieq ".exe") {');
  Lines.Add('            & $rebar3Exe compile');
  Lines.Add('        } else {');
  Lines.Add('            if ($null -eq $escriptCmd) {');
  Lines.Add('                Write-Fail "rebar3 found at $rebar3Exe but escript is not on PATH."');
  Lines.Add('                Pop-Location');
  Lines.Add('                exit 1');
  Lines.Add('            }');
  Lines.Add('            & $escriptCmd.Source $rebar3Exe compile');
  Lines.Add('        }');
  Lines.Add('        $rc = $LASTEXITCODE');
  Lines.Add('    } catch {');
  Lines.Add('        Write-Host "    exception: $($_.Exception.Message)" -ForegroundColor Red');
  Lines.Add('        $rc = 1');
  Lines.Add('    } finally {');
  Lines.Add('        Pop-Location');
  Lines.Add('    }');
  Lines.Add('    if ($rc -ne 0) {');
  Lines.Add('        Write-Fail "rebar3 compile failed (exit $rc)"');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    $ebinDir = Join-Path $GenDir ("_build\default\lib\" + $UnitName + "_abi\ebin")');
  Lines.Add('} else {');
  Lines.Add('    Write-Warn "rebar3 not found; falling back to erlc"');
  Lines.Add('    $ebinDir = Join-Path $GenDir "ebin"');
  Lines.Add('    if (-not (Test-Path -LiteralPath $ebinDir)) { New-Item -ItemType Directory -Path $ebinDir | Out-Null }');
  Lines.Add('    $erlSources = @(Get-ChildItem -LiteralPath $srcDir -Filter "*.erl" -File)');
  Lines.Add('    if ($erlSources.Count -eq 0) {');
  Lines.Add('        Write-Fail "No .erl files in src/"');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    $fulls = @($erlSources | ForEach-Object { $_.FullName })');
  Lines.Add('    & $erlcCmd.Source -o $ebinDir @fulls');
  Lines.Add('    if ($LASTEXITCODE -ne 0) {');
  Lines.Add('        Write-Fail "erlc failed (exit $LASTEXITCODE)"');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    $appSrc = Join-Path $srcDir "${UnitName}_abi.app.src"');
  Lines.Add('    if (Test-Path -LiteralPath $appSrc) {');
  Lines.Add('        Copy-Item -LiteralPath $appSrc -Destination (Join-Path $ebinDir "${UnitName}_abi.app") -Force');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $ebinDir)) {');
  Lines.Add('    Write-Fail "expected ebin dir does not exist: $ebinDir"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$beamCount = @(Get-ChildItem -LiteralPath $ebinDir -Filter "*.beam" -File).Count');
  Lines.Add('if ($beamCount -eq 0) {');
  Lines.Add('    Write-Fail "no .beam files in $ebinDir"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "Compiled $beamCount beam(s) to $ebinDir"');
  Lines.Add('');
end;

procedure EmitSmoke(Lines: TPascalStringList; const UnitName: SystemString);
var
  SvcMod, CallMod: SystemString;
begin
  SvcMod := UnitName + '_abi_service_main';
  CallMod := UnitName + '_abi_call_main';

  Lines.Add('if ($RunSmoke) {');
  Lines.Add('    Write-Info "Starting service..."');
  Lines.Add('    $svcLog = Join-Path $GenDir "smoke_service.out.log"');
  Lines.Add('    $svcErr = Join-Path $GenDir "smoke_service.err.log"');
  Lines.Add('    $svcEval = "' + #39 + SvcMod + #39 + ':main([])."');
  Lines.Add('    $svcArgs = @("-noshell", "-pa", $LingofuseEbin, "-pa", $ebinDir, "-eval", $svcEval)');
  Lines.Add('    $svcProc = Start-Process -FilePath $erlExe -ArgumentList $svcArgs -WorkingDirectory $GenDir -PassThru -NoNewWindow -RedirectStandardOutput $svcLog -RedirectStandardError $svcErr');
  Lines.Add('    Start-Sleep -Seconds 5');
  Lines.Add('');
  Lines.Add('    if ($null -ne $svcProc -and $svcProc.HasExited) {');
  Lines.Add('        Write-Fail "Service exited prematurely (code $($svcProc.ExitCode))."');
  Lines.Add('        if (Test-Path -LiteralPath $svcLog) {');
  Lines.Add('            Write-Host "--- service stdout ---" -ForegroundColor Yellow');
  Lines.Add('            Get-Content -LiteralPath $svcLog | ForEach-Object { Write-Host $_ }');
  Lines.Add('        }');
  Lines.Add('        if (Test-Path -LiteralPath $svcErr) {');
  Lines.Add('            Write-Host "--- service stderr ---" -ForegroundColor Yellow');
  Lines.Add('            Get-Content -LiteralPath $svcErr | ForEach-Object { Write-Host $_ }');
  Lines.Add('        }');
  Lines.Add('        exit 2');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    Write-Info "Running call test..."');
  Lines.Add('    $callEval = "' + #39 + CallMod + #39 + ':main([])."');
  Lines.Add('    $callArgs = @("-noshell", "-pa", $LingofuseEbin, "-pa", $ebinDir, "-eval", $callEval)');
  Lines.Add('    $callLog = Join-Path $GenDir "smoke_call.out.log"');
  Lines.Add('    $callErr = Join-Path $GenDir "smoke_call.err.log"');
  Lines.Add('    $callProc = Start-Process -FilePath $erlExe -ArgumentList $callArgs -WorkingDirectory $GenDir -PassThru -NoNewWindow -RedirectStandardOutput $callLog -RedirectStandardError $callErr -Wait');
  Lines.Add('    $callRc = $callProc.ExitCode');
  Lines.Add('');
  Lines.Add('    Start-Sleep -Milliseconds 500');
  Lines.Add('    if ($null -ne $svcProc -and -not $svcProc.HasExited) {');
  Lines.Add('        Stop-Process -Id $svcProc.Id -Force -ErrorAction SilentlyContinue');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (Test-Path -LiteralPath $callLog) {');
  Lines.Add('        Write-Host "--- call stdout ---" -ForegroundColor Yellow');
  Lines.Add('        Get-Content -LiteralPath $callLog | ForEach-Object { Write-Host $_ }');
  Lines.Add('    }');
  Lines.Add('    if (Test-Path -LiteralPath $callErr) {');
  Lines.Add('        $callErrText = Get-Content -LiteralPath $callErr -Raw');
  Lines.Add('        if ($callErrText) {');
  Lines.Add('            Write-Host "--- call stderr ---" -ForegroundColor Yellow');
  Lines.Add('            Write-Host $callErrText');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if ($callRc -ne 0) {');
  Lines.Add('        Write-Fail "Smoke test FAILED (client exit $callRc)"');
  Lines.Add('        if (Test-Path -LiteralPath $svcLog) {');
  Lines.Add('            Write-Host "--- service stdout (last 40 lines) ---" -ForegroundColor Yellow');
  Lines.Add('            Get-Content -LiteralPath $svcLog -Tail 40 | ForEach-Object { Write-Host $_ }');
  Lines.Add('        }');
  Lines.Add('        if (Test-Path -LiteralPath $svcErr) {');
  Lines.Add('            Write-Host "--- service stderr (last 40 lines) ---" -ForegroundColor Yellow');
  Lines.Add('            Get-Content -LiteralPath $svcErr -Tail 40 | ForEach-Object { Write-Host $_ }');
  Lines.Add('        }');
  Lines.Add('        exit 2');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "Smoke test PASSED."');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitNextSteps(Lines: TPascalStringList; const UnitName: SystemString);
var
  SvcMod, CallMod: SystemString;
begin
  SvcMod := UnitName + '_abi_service_main';
  CallMod := UnitName + '_abi_call_main';
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Environment ready." -ForegroundColor Green');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Terminal 1 (service):" -ForegroundColor Cyan');
  Lines.Add('Write-Host "    erl -noshell -pa ""$LingofuseEbin"" -pa ""$ebinDir"" -eval ""' + #39 + SvcMod + #39 + ':main([])."""');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Terminal 2 (call):" -ForegroundColor Cyan');
  Lines.Add('Write-Host "    erl -noshell -pa ""$LingofuseEbin"" -pa ""$ebinDir"" -eval ""' + #39 + CallMod + #39 + ':main([])."""');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Call test exits 0 when all checks PASS or SKIP; 2 if any FAIL."');
  Lines.Add('exit 0');
  Lines.Add('');
end;

function GenerateErlangTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
  U: SystemString;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;

  U := MakeApiName(Model.UnitName);

  Lines := TPascalStringList.Create;
  try
    EmitHeader(Lines);
    EmitHelp(Lines);
    EmitEbinResolver(Lines);
    EmitFindRebar3(Lines);
    EmitResolveEbin(Lines);
    EmitToolCheck(Lines);
    EmitUnitNameDetect(Lines);
    EmitCleanupStale(Lines);
    EmitLayout(Lines);
    EmitScaffold(Lines);
    EmitSanityCheck(Lines);
    EmitFileCheck(Lines);
    EmitBuild(Lines);
    EmitSmoke(Lines, U);
    EmitNextSteps(Lines, U);
    Result := Lines;
    Log('Generated setup_erlang_tests.ps1');
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterGenerator(
    'erlang',
    'setup_erlang_tests.ps1',
    gkPs1,
    'Erlang ABI test environment setup script',
    @GenerateErlangTestSetupScript);

end.
