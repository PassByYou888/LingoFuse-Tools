unit http_ts_abi_test_setup_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core, Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  code_decl_to_json_abi_registry;

function GenerateTsTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_ts_abi_test_setup_generator] %s', [Msg.Text]);
end;

procedure EmitHeader(Lines: TPascalStringList);
begin
  Lines.Add('#Requires -Version 5.1');
  Lines.Add('[CmdletBinding()]');
  Lines.Add('param(');
  Lines.Add('    [string]$TsLibDir = "",');
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
  Lines.Add('    Write-Host "Usage: setup_ts_tests.ps1 -TsLibDir <path> [options]"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Prepare the TypeScript test environment."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Required:"');
  Lines.Add('    Write-Host "  -TsLibDir <path>"');
  Lines.Add('    Write-Host "        Path to the lingofuse-ts package directory."');
  Lines.Add('    Write-Host "        Must contain package.json and src/index.ts."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Optional:"');
  Lines.Add('    Write-Host "  -GenDir <path>     Directory containing the generated .ts files."');
  Lines.Add('    Write-Host "                     Default: this script directory."');
  Lines.Add('    Write-Host "  -UnitName <name>   Source unit name (default: auto-detect)."');
  Lines.Add('    Write-Host "  -Force             Force reinstall of lingofuse-ts and tsx."');
  Lines.Add('    Write-Host "  -RunSmoke          Run the service-side smoke test after setup."');
  Lines.Add('    Write-Host "  -Help              Show this help."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    exit 0');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitValidation(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $TsLibDir) {');
  Lines.Add('    Write-Fail "-TsLibDir is required."');
  Lines.Add('    Write-Host "        Run ''setup_ts_tests.ps1 -Help'' for usage."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $TsLibDir)) {');
  Lines.Add('    Write-Fail "TsLibDir not found: $TsLibDir"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$TsLibDir = (Resolve-Path -LiteralPath $TsLibDir).Path');
  Lines.Add('');
  Lines.Add('$pkgJson = Join-Path $TsLibDir "package.json"');
  Lines.Add('if (-not (Test-Path -LiteralPath $pkgJson)) {');
  Lines.Add('    Write-Fail "Missing package.json under TsLibDir:"');
  Lines.Add('    Write-Fail "            $pkgJson"');
  Lines.Add('    Write-Fail "            -TsLibDir must point at the lingofuse-ts package source."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $GenDir) { $GenDir = $PSScriptRoot }');
  Lines.Add('$GenDir = (Resolve-Path -LiteralPath $GenDir).Path');
  Lines.Add('');
  Lines.Add('Write-Info "TsLibDir : $TsLibDir"');
  Lines.Add('Write-Info "GenDir   : $GenDir"');
  Lines.Add('');
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    $candidate = Get-ChildItem -LiteralPath $GenDir -Filter "*_http_json_service.ts" -File | Select-Object -First 1');
  Lines.Add('    if ($null -eq $candidate) {');
  Lines.Add('        Write-Fail "Cannot detect UnitName (no *_http_json_service.ts in $GenDir)."');
  Lines.Add('        Write-Fail "            Pass -UnitName explicitly."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    $UnitName = $candidate.Name -replace ''_http_json_service\.ts$'', ''''');
  Lines.Add('}');
  Lines.Add('Write-Info "UnitName : $UnitName"');
  Lines.Add('');
end;

procedure EmitToolCheck(Lines: TPascalStringList);
begin
  Lines.Add('$nodeCmd = Get-Command node -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $nodeCmd) {');
  Lines.Add('    Write-Fail "node.exe is not on PATH."');
  Lines.Add('    Write-Fail "            Install Node.js 18+ and add it to PATH."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$nodeVer = (& node --version 2>&1) -join ""');
  Lines.Add('Write-Ok "node $nodeVer"');
  Lines.Add('');
  Lines.Add('$npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $npmCmd) { $npmCmd = Get-Command npm -ErrorAction SilentlyContinue }');
  Lines.Add('if ($null -eq $npmCmd) {');
  Lines.Add('    Write-Fail "npm is not on PATH."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$npmVer = (& npm --version 2>&1) -join ""');
  Lines.Add('Write-Ok "npm  $npmVer"');
  Lines.Add('');
end;

procedure EmitFileCheck(Lines: TPascalStringList);
begin
  Lines.Add('$serviceFile = Join-Path $GenDir ("$UnitName" + "_http_json_service.ts")');
  Lines.Add('$serviceTest = Join-Path $GenDir ("$UnitName" + "_http_json_service_main_test___.ts")');
  Lines.Add('$callFile    = Join-Path $GenDir ("$UnitName" + "_http_json_call_ts.ts")');
  Lines.Add('$callTest    = Join-Path $GenDir ("$UnitName" + "_http_json_call_main_test___.ts")');
  Lines.Add('');
  Lines.Add('$missing = @()');
  Lines.Add('foreach ($p in @($serviceFile, $serviceTest, $callFile, $callTest)) {');
  Lines.Add('    if (-not (Test-Path -LiteralPath $p)) { $missing += $p }');
  Lines.Add('}');
  Lines.Add('if ($missing.Count -gt 0) {');
  Lines.Add('    Write-Fail "Missing generated files:"');
  Lines.Add('    foreach ($m in $missing) { Write-Host "        $m" }');
  Lines.Add('    Write-Fail "Generate the artifacts first, then re-run this script."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "All four generated TS files present."');
  Lines.Add('');
end;

procedure EmitEnsureDist(Lines: TPascalStringList);
begin
  Lines.Add('$distJs   = Join-Path $TsLibDir "dist\index.js"');
  Lines.Add('$distDts  = Join-Path $TsLibDir "dist\index.d.ts"');
  Lines.Add('$srcIndex = Join-Path $TsLibDir "src\index.ts"');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $srcIndex)) {');
  Lines.Add('    Write-Fail "TsLibDir is missing src\index.ts:"');
  Lines.Add('    Write-Fail "            $srcIndex"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if ((-not (Test-Path -LiteralPath $distJs)) -or (-not (Test-Path -LiteralPath $distDts))) {');
  Lines.Add('    Write-Info "dist\ is missing or incomplete; running npm install + npm run build in TsLibDir ..."');
  Lines.Add('    Push-Location $TsLibDir');
  Lines.Add('    try {');
  Lines.Add('        $tsLibNodeModules = Join-Path $TsLibDir "node_modules"');
  Lines.Add('        if (-not (Test-Path -LiteralPath $tsLibNodeModules)) {');
  Lines.Add('            & npm install --no-audit --no-fund --loglevel=error');
  Lines.Add('            if ($LASTEXITCODE -ne 0) {');
  Lines.Add('                Write-Fail "npm install in TsLibDir failed (exit $LASTEXITCODE)."');
  Lines.Add('                exit 1');
  Lines.Add('            }');
  Lines.Add('        }');
  Lines.Add('        & npm run build');
  Lines.Add('        if ($LASTEXITCODE -ne 0) {');
  Lines.Add('            Write-Fail "npm run build in TsLibDir failed (exit $LASTEXITCODE)."');
  Lines.Add('            exit 1');
  Lines.Add('        }');
  Lines.Add('    } finally {');
  Lines.Add('        Pop-Location');
  Lines.Add('    }');
  Lines.Add('    if (-not (Test-Path -LiteralPath $distJs)) {');
  Lines.Add('        Write-Fail "Build finished but $distJs is still missing."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "lingofuse-ts built successfully."');
  Lines.Add('} else {');
  Lines.Add('    Write-Ok "lingofuse-ts dist\ present."');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitInstallAllPackages(Lines: TPascalStringList);
begin
  Lines.Add('$nodeModules = Join-Path $GenDir "node_modules"');
  Lines.Add('if (-not (Test-Path -LiteralPath $nodeModules)) {');
  Lines.Add('    New-Item -ItemType Directory -Path $nodeModules | Out-Null');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$targetTsPkg = Join-Path $nodeModules "lingofuse-ts"');
  Lines.Add('$tsxBin      = Join-Path $nodeModules ".bin\tsx.cmd"');
  Lines.Add('');
  Lines.Add('if ($Force) {');
  Lines.Add('    if (Test-Path -LiteralPath $targetTsPkg) {');
  Lines.Add('        Write-Info "Force: removing existing lingofuse-ts"');
  Lines.Add('        Remove-Item -LiteralPath $targetTsPkg -Recurse -Force');
  Lines.Add('    }');
  Lines.Add('    if (Test-Path -LiteralPath $tsxBin) {');
  Lines.Add('        Write-Info "Force: removing existing tsx"');
  Lines.Add('        Remove-Item -LiteralPath $tsxBin -Force -ErrorAction SilentlyContinue');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$needTs  = -not (Test-Path -LiteralPath $targetTsPkg)');
  Lines.Add('$needTsx = -not (Test-Path -LiteralPath $tsxBin)');
  Lines.Add('');
  Lines.Add('if (-not ($needTs -or $needTsx)) {');
  Lines.Add('    Write-Ok "All required packages already present."');
  Lines.Add('} else {');
  Lines.Add('    $packages = @()');
  Lines.Add('    $packages += $TsLibDir');
  Lines.Add('    $packages += "tsx"');
  Lines.Add('');
  Lines.Add('    $installArgs = @("install", "--no-save", "--no-audit", "--no-fund", "--loglevel=error") + $packages');
  Lines.Add('');
  Lines.Add('    Write-Info "Installing in a single npm call:"');
  Lines.Add('    foreach ($pkg in $packages) { Write-Host "        $pkg" }');
  Lines.Add('');
  Lines.Add('    Push-Location $GenDir');
  Lines.Add('    try {');
  Lines.Add('        & npm @installArgs');
  Lines.Add('        if ($LASTEXITCODE -ne 0) {');
  Lines.Add('            Write-Fail "npm install failed (exit $LASTEXITCODE)."');
  Lines.Add('            exit 1');
  Lines.Add('        }');
  Lines.Add('    } finally {');
  Lines.Add('        Pop-Location');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    if (-not (Test-Path -LiteralPath $targetTsPkg)) {');
  Lines.Add('        Write-Fail "npm install returned success but lingofuse-ts is still missing."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    if (-not (Test-Path -LiteralPath $tsxBin)) {');
  Lines.Add('        Write-Fail "npm install returned success but tsx is still missing."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    Write-Ok "All required packages installed."');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitNextSteps(Lines: TPascalStringList);
begin
  Lines.Add('$smokeCmd = ".\node_modules\.bin\tsx.cmd .\$UnitName" + "_http_json_service_main_test___.ts --smoke"');
  Lines.Add('$callCmd  = ".\node_modules\.bin\tsx.cmd .\$UnitName" + "_http_json_call_main_test___.ts"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Ready. Next steps:" -ForegroundColor Green');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  Smoke test (no bridge needed):" -ForegroundColor Cyan');
  Lines.Add('Write-Host "      cd `"$GenDir`""');
  Lines.Add('Write-Host "      $smokeCmd"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  End-to-end call test (3 terminals):" -ForegroundColor Cyan');
  Lines.Add('Write-Host "    [A] start service:"');
  Lines.Add('Write-Host "          cd `"$GenDir`""');
  Lines.Add('Write-Host "          .\node_modules\.bin\tsx.cmd .\$UnitName`_http_json_service.ts"');
  Lines.Add('Write-Host "    [B] start bridge (run in ComplexTestUnit2 dir):"');
  Lines.Add('Write-Host "          .\launch_bridge.ps1"');
  Lines.Add('Write-Host "    [C] run call test:"');
  Lines.Add('Write-Host "          cd `"$GenDir`""');
  Lines.Add('Write-Host "          $callCmd"');
  Lines.Add('Write-Host ""');
  Lines.Add('');
  Lines.Add('if ($RunSmoke) {');
  Lines.Add('    Write-Info "Running service-side smoke test ..."');
  Lines.Add('    Push-Location $GenDir');
  Lines.Add('    try {');
  Lines.Add('        & ".\node_modules\.bin\tsx.cmd" ("$UnitName" + "_http_json_service_main_test___.ts") --smoke');
  Lines.Add('        $smokeRc = $LASTEXITCODE');
  Lines.Add('    } finally {');
  Lines.Add('        Pop-Location');
  Lines.Add('    }');
  Lines.Add('    if ($smokeRc -ne 0) {');
  Lines.Add('        Write-Fail "smoke test failed (exit $smokeRc)."');
  Lines.Add('        exit $smokeRc');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "smoke test passed."');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('exit 0');
end;

function GenerateTsTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;

  Lines := TPascalStringList.Create;
  try
    EmitHeader(Lines);
    EmitHelp(Lines);
    EmitValidation(Lines);
    EmitToolCheck(Lines);
    EmitFileCheck(Lines);
    EmitEnsureDist(Lines);
    EmitInstallAllPackages(Lines);
    EmitNextSteps(Lines);
    Result := Lines;
    Log('Generated setup_ts_tests.ps1');
  finally
    if Result <> Lines then Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'typescript', 'TypeScript HTTP/JSON test setup script',
    asBoth, akBuildScript,
    'setup_ts_tests.ps1', True,
    @GenerateTsTestSetupScript);

end.
