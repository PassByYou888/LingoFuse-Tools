unit go_abi_test_setup_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.UnicodeMixedLib,
  Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateGoTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;

implementation

procedure EmitHeader(Lines: TPascalStringList);
begin
  Lines.Add('#Requires -Version 5.1');
  Lines.Add('');
  Lines.Add('[CmdletBinding()]');
  Lines.Add('param(');
  Lines.Add('    [string]$LingoFuseGo = "",');
  Lines.Add('    [string]$GenDir = "",');
  Lines.Add('    [string]$UnitName = "",');
  Lines.Add('    [string]$GOPROXY = "https://goproxy.cn,direct",');
  Lines.Add('    [switch]$Force,');
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
  Lines.Add('    Write-Host "Usage: setup_go_tests.ps1 -LingoFuseGo <path> [-GenDir <path>] [-UnitName <name>] [-GOPROXY <url>] [-Force] [-Clean] [-Help]"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "One-shot Go test environment bootstrap for LingoFuse ABI generated code."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "How it works:"');
  Lines.Add('    Write-Host "  1. Copy the two library files (<unit>_abi_call.go, <unit>_abi_service.go)"');
  Lines.Add('    Write-Host "     into a clean build directory (<GenDir>/.go_clean_build/), together"');
  Lines.Add('    Write-Host "     with go.mod and go.sum."');
  Lines.Add('    Write-Host "  2. Move the two test programs into package-isolated subdirectories and"');
  Lines.Add('    Write-Host "     rename them to main.go so that go build ./... can compile them:"');
  Lines.Add('    Write-Host "         <unit>_abi_service_test.go -> <unit>_abi_service_test/main.go"');
  Lines.Add('    Write-Host "         <unit>_abi_call_test.go    -> <unit>_abi_call_test/main.go"');
  Lines.Add('    Write-Host "  3. Non-Go files (.cpp, .h, .pas, .cs, .py, .rs, ...) are NOT copied,"');
  Lines.Add('    Write-Host "     so co-located outputs from other language generators never interfere."');
  Lines.Add('    Write-Host "  4. Build and vet run inside the clean directory."');
  Lines.Add('    Write-Host "  5. After setup, run the service and call test programs in two terminals:"');
  Lines.Add('    Write-Host "         go run ./<unit>_abi_service_test"');
  Lines.Add('    Write-Host "         go run ./<unit>_abi_call_test"');
  Lines.Add('    Write-Host "  6. The clean directory is KEPT on success by default, so you can inspect it."');
  Lines.Add('    Write-Host "     Use -Clean to delete it afterwards."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Required:"');
  Lines.Add('    Write-Host "  -LingoFuseGo <path>"');
  Lines.Add('    Write-Host "        Path to the github.com/PassByYou888/LingoFuse/go module source directory."');
  Lines.Add('    Write-Host "        Must contain go.mod."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Optional:"');
  Lines.Add('    Write-Host "  -GenDir <path>     Generated Go project directory. Default: this script directory."');
  Lines.Add('    Write-Host "  -UnitName <name>   Source unit name. Default: auto-detect from go.mod or *_abi_call.go."');
  Lines.Add('    Write-Host "  -GOPROXY <url>     Go module proxy used during go mod tidy."');
  Lines.Add('    Write-Host "                     Default: https://goproxy.cn,direct (China mirror)."');
  Lines.Add('    Write-Host "                     Pass an empty string to keep the current GOPROXY."');
  Lines.Add('    Write-Host "  -Force             Recreate the clean build directory from scratch."');
  Lines.Add('    Write-Host "  -Clean             Delete the clean build directory on success."');
  Lines.Add('    Write-Host "  -Help              Show this help."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Examples:"');
  Lines.Add('    Write-Host "  .\setup_go_tests.ps1 -LingoFuseGo D:\CoreLibrary\LingoFuse\go"');
  Lines.Add('    Write-Host "  .\setup_go_tests.ps1 -LingoFuseGo D:\CoreLibrary\LingoFuse\go -Clean"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Exit codes:"');
  Lines.Add('    Write-Host "  0   success"');
  Lines.Add('    Write-Host "  1   validation failed, missing tool, or build failed"');
  Lines.Add('    exit 0');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitValidation(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $LingoFuseGo) {');
  Lines.Add('    Write-Fail "-LingoFuseGo is required."');
  Lines.Add('    Write-Fail "        Pass the path to the LingoFuse Go module directory."');
  Lines.Add('    Write-Fail "        Example: -LingoFuseGo D:\CoreLibrary\LingoFuse\go"');
  Lines.Add('    Write-Fail "        Run setup_go_tests.ps1 -Help for usage."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $LingoFuseGo)) {');
  Lines.Add('    Write-Fail "LingoFuseGo not found: $LingoFuseGo"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$LingoFuseGo = (Resolve-Path -LiteralPath $LingoFuseGo).Path');
  Lines.Add('');
  Lines.Add('$lingofuseGoMod = Join-Path $LingoFuseGo "go.mod"');
  Lines.Add('if (-not (Test-Path -LiteralPath $lingofuseGoMod)) {');
  Lines.Add('    Write-Fail "Missing go.mod in LingoFuseGo:"');
  Lines.Add('    Write-Fail "            $lingofuseGoMod"');
  Lines.Add('    Write-Fail "            -LingoFuseGo must point at the LingoFuse Go module source directory."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $GenDir) { $GenDir = $PSScriptRoot }');
  Lines.Add('if (-not (Test-Path -LiteralPath $GenDir)) {');
  Lines.Add('    Write-Fail "GenDir not found: $GenDir"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$GenDir = (Resolve-Path -LiteralPath $GenDir).Path');
  Lines.Add('');
  Lines.Add('$normalizedLingofuseGo = $LingoFuseGo.Replace([string][char]92, [string][char]47)');
  Lines.Add('');
  Lines.Add('Write-Info "GenDir      : $GenDir"');
  Lines.Add('Write-Info "LingoFuseGo : $LingoFuseGo"');
  Lines.Add('Write-Info "Go path     : $normalizedLingofuseGo"');
  Lines.Add('if ($GOPROXY) {');
  Lines.Add('    Write-Info "GOPROXY     : $GOPROXY"');
  Lines.Add('} else {');
  Lines.Add('    Write-Info "GOPROXY     : (keep current $env:GOPROXY)"');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitToolCheck(Lines: TPascalStringList);
begin
  Lines.Add('$goCmd = Get-Command go -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $goCmd) {');
  Lines.Add('    Write-Fail "go is not on PATH."');
  Lines.Add('    Write-Fail "        Install Go: https://go.dev/dl/"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$goVer = (& go version 2>&1) -join ""');
  Lines.Add('Write-Ok "go $goVer"');
  Lines.Add('');
  Lines.Add('$gofmtCmd = Get-Command gofmt -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $gofmtCmd) {');
  Lines.Add('    Write-Fail "gofmt is not on PATH."');
  Lines.Add('    Write-Fail "        Install Go: https://go.dev/dl/"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitUnitNameDetect(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    $goModPath = Join-Path $GenDir "go.mod"');
  Lines.Add('    if (Test-Path -LiteralPath $goModPath) {');
  Lines.Add('        $content = Get-Content -LiteralPath $goModPath -Raw');
  Lines.Add('        if ($content -match ' + #39 + '(?m)^\s*module\s+(\S+)\s*$' + #39 + ') {');
  Lines.Add('            $mod = $matches[1]');
  Lines.Add('            $lastSeg = ($mod -split ' + #39 + '/' + #39 + ')[-1]');
  Lines.Add('            if ($lastSeg -match ' + #39 + '^(.+)_abi$' + #39 + ') {');
  Lines.Add('                $UnitName = $matches[1]');
  Lines.Add('            } else {');
  Lines.Add('                $UnitName = $lastSeg');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('    if (-not $UnitName) {');
  Lines.Add('        $cand = Get-ChildItem -LiteralPath $GenDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ' + #39 + '*_abi_call.go' + #39 + ' } | Select-Object -First 1');
  Lines.Add('        if ($null -ne $cand) {');
  Lines.Add('            $UnitName = $cand.Name -replace ' + #39 + '_abi_call\.go$' + #39 + ', ' + #39 + #39);
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('    if (-not $UnitName) {');
  Lines.Add('        Write-Fail "Cannot auto-detect UnitName (no go.mod and no *_abi_call.go)."');
  Lines.Add('        Write-Fail "        Pass -UnitName explicitly."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('Write-Info "UnitName: $UnitName"');
  Lines.Add('');
end;

procedure EmitFileCheck(Lines: TPascalStringList);
begin
  Lines.Add('$callGo        = Join-Path $GenDir "${UnitName}_abi_call.go"');
  Lines.Add('$serviceGo     = Join-Path $GenDir "${UnitName}_abi_service.go"');
  Lines.Add('$serviceTestGo = Join-Path $GenDir "${UnitName}_abi_service_test.go"');
  Lines.Add('$callTestGo    = Join-Path $GenDir "${UnitName}_abi_call_test.go"');
  Lines.Add('');
  Lines.Add('$missing = @()');
  Lines.Add('foreach ($p in @($callGo, $serviceGo)) {');
  Lines.Add('    if (-not (Test-Path -LiteralPath $p)) {');
  Lines.Add('        $missing += $p');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('if ($missing.Count -gt 0) {');
  Lines.Add('    Write-Fail "Missing generated Go library files:"');
  Lines.Add('    foreach ($m in $missing) { Write-Host "        $m" }');
  Lines.Add('    Write-Fail "Run code_decl_to_abi first to emit the .go files."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "Generated library files present."');
  Lines.Add('');
  Lines.Add('$missingTest = @()');
  Lines.Add('foreach ($p in @($serviceTestGo, $callTestGo)) {');
  Lines.Add('    if (-not (Test-Path -LiteralPath $p)) {');
  Lines.Add('        $missingTest += $p');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('if ($missingTest.Count -gt 0) {');
  Lines.Add('    Write-Warn "Missing test program source file(s):"');
  Lines.Add('    foreach ($m in $missingTest) { Write-Host "        $m" }');
  Lines.Add('    Write-Warn "Re-run code_decl_to_abi with the Go target to regenerate them."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "Test program sources present."');
  Lines.Add('');
end;

procedure EmitSanityCheck(Lines: TPascalStringList);
begin
  Lines.Add('$stalePattern = ' + #39 + '(?m)\b(?:var|func|type)\s+\w+\s*[:(]\s*(?:integer|double|single|extended|real|smallint|cardinal|uint64|word|byte|longint)\b' + #39 + ';');
  Lines.Add('$staleFiles = @()');
  Lines.Add('foreach ($rel in @("${UnitName}_abi_call.go", "${UnitName}_abi_service.go")) {');
  Lines.Add('    $p = Join-Path $GenDir $rel');
  Lines.Add('    $c = Get-Content -LiteralPath $p -Raw');
  Lines.Add('    if ($c -match $stalePattern) {');
  Lines.Add('        $staleFiles += $rel');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('if ($staleFiles.Count -gt 0) {');
  Lines.Add('    Write-Fail "Stale Go files detected (Pascal type names in Go type positions):"');
  Lines.Add('    foreach ($s in $staleFiles) { Write-Host "        $s" }');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Fail "These .go files were produced by an OLD Go generator."');
  Lines.Add('    Write-Fail "Re-run: code_decl_to_abi <input> <output.go>"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "Sanity check passed."');
  Lines.Add('');
end;

procedure EmitCopyToCleanDir(Lines: TPascalStringList);
begin
  Lines.Add('$cleanDir = Join-Path $GenDir ".go_clean_build"');
  Lines.Add('');
  Lines.Add('if ($Force -and (Test-Path -LiteralPath $cleanDir)) {');
  Lines.Add('    Write-Info "Force: removing existing clean build directory."');
  Lines.Add('    Remove-Item -LiteralPath $cleanDir -Recurse -Force');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $cleanDir)) {');
  Lines.Add('    New-Item -ItemType Directory -Path $cleanDir -Force | Out-Null');
  Lines.Add('    Write-Ok "Created clean build directory: $cleanDir"');
  Lines.Add('} else {');
  Lines.Add('    Write-Info "Reusing clean build directory: $cleanDir"');
  Lines.Add('    Get-ChildItem -LiteralPath $cleanDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$copiedGo = 0');
  Lines.Add('$skippedOld = 0');
  Lines.Add('Get-ChildItem -LiteralPath $GenDir -Filter "*.go" -File -ErrorAction SilentlyContinue | ForEach-Object {');
  Lines.Add('    $n = $_.Name');
  Lines.Add('    if ($n -like "*_abi_service_test.go") { return }');
  Lines.Add('    if ($n -like "*_abi_call_test.go") { return }');
  Lines.Add('    if ($n -like "*_abi_test.go") { $skippedOld++; return }');
  Lines.Add('    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $cleanDir $n) -Force');
  Lines.Add('    $copiedGo++');
  Lines.Add('}');
  Lines.Add('if ($copiedGo -eq 0) {');
  Lines.Add('    Write-Fail "No library .go files found in $GenDir"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "Copied $copiedGo library .go file(s) into clean directory."');
  Lines.Add('if ($skippedOld -gt 0) {');
  Lines.Add('    Write-Info "Skipped $skippedOld stale *_abi_test.go file(s)."');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$srcGoMod = Join-Path $GenDir "go.mod"');
  Lines.Add('if (Test-Path -LiteralPath $srcGoMod) {');
  Lines.Add('    Copy-Item -LiteralPath $srcGoMod -Destination (Join-Path $cleanDir "go.mod") -Force');
  Lines.Add('    Write-Info "Copied go.mod."');
  Lines.Add('}');
  Lines.Add('$srcGoSum = Join-Path $GenDir "go.sum"');
  Lines.Add('if (Test-Path -LiteralPath $srcGoSum) {');
  Lines.Add('    Copy-Item -LiteralPath $srcGoSum -Destination (Join-Path $cleanDir "go.sum") -Force');
  Lines.Add('    Write-Info "Copied go.sum."');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$testMoves = @(');
  Lines.Add('    @{ Src = "${UnitName}_abi_service_test.go"; Dst = "${UnitName}_abi_service_test" }');
  Lines.Add('    @{ Src = "${UnitName}_abi_call_test.go";    Dst = "${UnitName}_abi_call_test"    }');
  Lines.Add(')');
  Lines.Add('foreach ($t in $testMoves) {');
  Lines.Add('    $srcFile = Join-Path $GenDir $t.Src');
  Lines.Add('    $dstDir  = Join-Path $cleanDir $t.Dst');
  Lines.Add('    if (-not (Test-Path -LiteralPath $srcFile)) {');
  Lines.Add('        Write-Fail "Test source missing: $srcFile"');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    if (Test-Path -LiteralPath $dstDir) {');
  Lines.Add('        Remove-Item -LiteralPath $dstDir -Recurse -Force');
  Lines.Add('    }');
  Lines.Add('    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null');
  Lines.Add('    $dstFile = Join-Path $dstDir "main.go"');
  Lines.Add('    Copy-Item -LiteralPath $srcFile -Destination $dstFile -Force');
  Lines.Add('    Write-Info "Copied $($t.Src) -> $($t.Dst)/main.go"');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$nonGoExts = @(".cpp", ".cc", ".cxx", ".c", ".h", ".hpp", ".hh", ".pas", ".pp", ".p", ".cs", ".py", ".rs")');
  Lines.Add('$contaminants = @(Get-ChildItem -LiteralPath $cleanDir -File -ErrorAction SilentlyContinue | Where-Object { $nonGoExts -contains $_.Extension })');
  Lines.Add('if ($contaminants.Count -gt 0) {');
  Lines.Add('    Write-Fail "Clean directory top-level contains non-Go files:"');
  Lines.Add('    foreach ($f in $contaminants) { Write-Host "        $($f.Name)" }');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "Clean directory top-level verified: Go-only."');
  Lines.Add('');
end;

procedure EmitGoModInCleanDir(Lines: TPascalStringList);
begin
  Lines.Add('$goModPath = Join-Path $cleanDir "go.mod"');
  Lines.Add('if (-not (Test-Path -LiteralPath $goModPath)) {');
  Lines.Add('    $moduleName = "local/${UnitName}_abi"');
  Lines.Add('    $content = "module $moduleName`n`ngo 1.21`n`nrequire github.com/PassByYou888/LingoFuse/go v0.0.0`n`nreplace github.com/PassByYou888/LingoFuse/go => $normalizedLingofuseGo`n"');
  Lines.Add('    Write-TextFileNoBom -Path $goModPath -Content $content');
  Lines.Add('    Write-Ok "Created go.mod in clean directory."');
  Lines.Add('} else {');
  Lines.Add('    Write-Info "Clean go.mod exists; verifying require + replace directives."');
  Lines.Add('    $existing = Get-Content -LiteralPath $goModPath -Raw');
  Lines.Add('    $appendLines = @()');
  Lines.Add('    if ($existing -notmatch ' + #39 + 'require\s+github\.com/PassByYou888/LingoFuse/go\b' + #39 + ') {');
  Lines.Add('        $appendLines += "require github.com/PassByYou888/LingoFuse/go v0.0.0"');
  Lines.Add('    }');
  Lines.Add('    if ($existing -notmatch ' + #39 + 'replace\s+github\.com/PassByYou888/LingoFuse/go\b' + #39 + ') {');
  Lines.Add('        $appendLines += "replace github.com/PassByYou888/LingoFuse/go => $normalizedLingofuseGo"');
  Lines.Add('    }');
  Lines.Add('    if ($appendLines.Count -gt 0) {');
  Lines.Add('        $newContent = $existing.TrimEnd() + "`n`n" + ($appendLines -join "`n") + "`n"');
  Lines.Add('        Write-TextFileNoBom -Path $goModPath -Content $newContent');
  Lines.Add('        Write-Ok "Injected missing directives into clean go.mod:"');
  Lines.Add('        foreach ($l in $appendLines) { Write-Info "    + $l" }');
  Lines.Add('    } else {');
  Lines.Add('        Write-Ok "Clean go.mod already has require and replace directives."');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitBuild(Lines: TPascalStringList);
begin
  Lines.Add('$savedGOPROXY = $env:GOPROXY');
  Lines.Add('$savedGOSUMDB = $env:GOSUMDB');
  Lines.Add('$savedGONOSUMDB = $env:GONOSUMDB');
  Lines.Add('Push-Location $cleanDir');
  Lines.Add('try {');
  Lines.Add('    if ($GOPROXY) {');
  Lines.Add('        $env:GOPROXY = $GOPROXY');
  Lines.Add('        $env:GOSUMDB = "off"');
  Lines.Add('        $env:GONOSUMDB = "*"');
  Lines.Add('        Write-Info "GOPROXY set to $GOPROXY (GOSUMDB=off)."');
  Lines.Add('    } else {');
  Lines.Add('        Write-Info "Using existing GOPROXY=$env:GOPROXY."');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    Write-Info "Running go mod tidy ..."');
  Lines.Add('    & go mod tidy');
  Lines.Add('    $rc = $LASTEXITCODE');
  Lines.Add('    if ($rc -ne 0) {');
  Lines.Add('        Write-Fail "go mod tidy failed (exit $rc)."');
  Lines.Add('        Write-Fail "        - LingoFuse go is resolved locally via replace:"');
  Lines.Add('        Write-Fail "            $LingoFuseGo"');
  Lines.Add('        Write-Fail "        - Only indirect deps (github.com/ebitengine/purego) are downloaded."');
  Lines.Add('        Write-Fail "        - If that download failed, try another proxy, e.g.:"');
  Lines.Add('        Write-Fail "            -GOPROXY https://mirrors.aliyun.com/goproxy/,direct"');
  Lines.Add('        Write-Fail "            -GOPROXY https://goproxy.io,direct"');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "go mod tidy passed."');
  Lines.Add('');
  Lines.Add('    Write-Info "Running gofmt -w . (normalize line endings and formatting) ..."');
  Lines.Add('    & gofmt -w .');
  Lines.Add('    $rc = $LASTEXITCODE');
  Lines.Add('    if ($rc -ne 0) {');
  Lines.Add('        Write-Fail "gofmt -w failed (exit $rc)."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "gofmt -w passed."');
  Lines.Add('');
  Lines.Add('    Write-Info "Running gofmt -l . (verify) ..."');
  Lines.Add('    $unformatted = ((& gofmt -l . 2>&1) -join "").Trim()');
  Lines.Add('    if ($unformatted -ne "") {');
  Lines.Add('        Write-Fail "gofmt -l still reports files after gofmt -w (unexpected):"');
  Lines.Add('        Write-Host $unformatted');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "gofmt check passed."');
  Lines.Add('');
  Lines.Add('    Write-Info "Running go build ./... ..."');
  Lines.Add('    & go build ./...');
  Lines.Add('    $rc = $LASTEXITCODE');
  Lines.Add('    if ($rc -ne 0) {');
  Lines.Add('        Write-Fail "go build failed (exit $rc)."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "go build passed."');
  Lines.Add('');
  Lines.Add('    Write-Info "Running go vet ./... ..."');
  Lines.Add('    & go vet ./...');
  Lines.Add('    $rc = $LASTEXITCODE');
  Lines.Add('    if ($rc -ne 0) {');
  Lines.Add('        Write-Fail "go vet failed (exit $rc)."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "go vet passed."');
  Lines.Add('');
  Lines.Add('} finally {');
  Lines.Add('    $env:GOPROXY = $savedGOPROXY');
  Lines.Add('    $env:GOSUMDB = $savedGOSUMDB');
  Lines.Add('    $env:GONOSUMDB = $savedGONOSUMDB');
  Lines.Add('    Pop-Location');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitNextSteps(Lines: TPascalStringList);
begin
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Environment is ready." -ForegroundColor Green');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Clean build directory: $cleanDir" -ForegroundColor Cyan');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Clean directory layout:" -ForegroundColor Cyan');
  Lines.Add('Write-Host "  <unit>_abi_call.go                     (library, package <unit>_abi)"');
  Lines.Add('Write-Host "  <unit>_abi_service.go                  (library, package <unit>_abi)"');
  Lines.Add('Write-Host "  go.mod / go.sum"');
  Lines.Add('Write-Host "  <unit>_abi_service_test/main.go        (package main)"');
  Lines.Add('Write-Host "  <unit>_abi_call_test/main.go           (package main)"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Run the two test programs in two separate terminals:" -ForegroundColor Cyan');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  Terminal 1 (service):" -ForegroundColor Yellow');
  Lines.Add('Write-Host "      cd `"$cleanDir`""');
  Lines.Add('Write-Host "      go run ./${UnitName}_abi_service_test"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  Terminal 2 (call):" -ForegroundColor Yellow');
  Lines.Add('Write-Host "      cd `"$cleanDir`""');
  Lines.Add('Write-Host "      go run ./${UnitName}_abi_call_test"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "The service program waits for Enter; press Enter to stop it." -ForegroundColor DarkGray');
  Lines.Add('Write-Host "The call program exits with code 0 when all tests pass, 2 otherwise." -ForegroundColor DarkGray');
  Lines.Add('Write-Host ""');
  Lines.Add('if ($Clean) {');
  Lines.Add('    if (Test-Path -LiteralPath $cleanDir) {');
  Lines.Add('        Remove-Item -LiteralPath $cleanDir -Recurse -Force');
  Lines.Add('        Write-Info "Cleaned up: $cleanDir"');
  Lines.Add('    }');
  Lines.Add('} else {');
  Lines.Add('    Write-Host "Use -Clean next time to delete the clean directory." -ForegroundColor DarkGray');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('exit 0');
  Lines.Add('');
end;

function GenerateGoTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;

  Lines := TPascalStringList.Create;
  try
    EmitHeader(Lines);
    EmitHelp(Lines);
    EmitValidation(Lines);
    EmitToolCheck(Lines);
    EmitUnitNameDetect(Lines);
    EmitFileCheck(Lines);
    EmitSanityCheck(Lines);
    EmitCopyToCleanDir(Lines);
    EmitGoModInCleanDir(Lines);
    EmitBuild(Lines);
    EmitNextSteps(Lines);
    Result := Lines;
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization

  RegisterGenerator(
    'go',
    'setup_go_tests.ps1',
    gkPs1,
    'Go ABI test environment setup script',
    @GenerateGoTestSetupScript);

end.
