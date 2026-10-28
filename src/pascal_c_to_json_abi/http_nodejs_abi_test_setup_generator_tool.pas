unit http_nodejs_abi_test_setup_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core, Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  code_decl_to_json_abi_registry;

function GenerateJsTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

procedure Log(const Msg: TP_String);
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_nodejs_abi_test_setup_generator] %s', [Msg.Text]);
end;

procedure EmitHeader(Lines: TPascalStringList);
begin
  Lines.Add('#Requires -Version 5.1');
  Lines.Add('[CmdletBinding()]');
  Lines.Add('param(');
  Lines.Add('    [string]$JsLibDir = "",');
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
  Lines.Add('    Write-Host "Usage: setup_js_tests.ps1 -JsLibDir <path> [options]"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Prepare the Node.js test environment."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Required:"');
  Lines.Add('    Write-Host "  -JsLibDir <path>"');
  Lines.Add('    Write-Host "        Path to the lingofuse-js package directory."');
  Lines.Add('    Write-Host "        Must contain package.json."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Optional:"');
  Lines.Add('    Write-Host "  -GenDir <path>     Directory containing the generated .js files."');
  Lines.Add('    Write-Host "                     Default: this script directory."');
  Lines.Add('    Write-Host "  -UnitName <name>   Source unit name (default: auto-detect)."');
  Lines.Add('    Write-Host "  -Force             Force reinstall of lingofuse-js."');
  Lines.Add('    Write-Host "  -RunSmoke          Run the service-side smoke test after setup."');
  Lines.Add('    Write-Host "  -Help              Show this help."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Exit codes:"');
  Lines.Add('    Write-Host "  0   success (or -Help was requested)"');
  Lines.Add('    Write-Host "  1   validation failed, missing file, or install failed"');
  Lines.Add('    exit 0');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitValidation(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $JsLibDir) {');
  Lines.Add('    Write-Fail "-JsLibDir is required."');
  Lines.Add('    Write-Host "        Run ''setup_js_tests.ps1 -Help'' for usage."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $JsLibDir)) {');
  Lines.Add('    Write-Fail "JsLibDir not found: $JsLibDir"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$JsLibDir = (Resolve-Path -LiteralPath $JsLibDir).Path');
  Lines.Add('');
  Lines.Add('$pkgJson = Join-Path $JsLibDir "package.json"');
  Lines.Add('if (-not (Test-Path -LiteralPath $pkgJson)) {');
  Lines.Add('    Write-Fail "Missing package.json under JsLibDir:"');
  Lines.Add('    Write-Fail "            $pkgJson"');
  Lines.Add('    Write-Fail "            -JsLibDir must point at the lingofuse-js package source."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $GenDir) { $GenDir = $PSScriptRoot }');
  Lines.Add('$GenDir = (Resolve-Path -LiteralPath $GenDir).Path');
  Lines.Add('');
  Lines.Add('Write-Info "JsLibDir : $JsLibDir"');
  Lines.Add('Write-Info "GenDir   : $GenDir"');
  Lines.Add('');
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    $candidate = Get-ChildItem -LiteralPath $GenDir -Filter "*_http_json_service_node.js" -File | Select-Object -First 1');
  Lines.Add('    if ($null -eq $candidate) {');
  Lines.Add('        Write-Fail "Cannot detect UnitName (no *_http_json_service_node.js in $GenDir)."');
  Lines.Add('        Write-Fail "            Pass -UnitName explicitly."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    $UnitName = $candidate.Name -replace ''_http_json_service_node\.js$'', ''''');
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
  Lines.Add('if ($null -eq $npmCmd) {');
  Lines.Add('    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue');
  Lines.Add('}');
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
  Lines.Add('$serviceFile    = Join-Path $GenDir ("$UnitName" + "_http_json_service_node.js")');
  Lines.Add('$serviceTest    = Join-Path $GenDir ("$UnitName" + "_http_json_service_main_test___.js")');
  Lines.Add('$callFile       = Join-Path $GenDir ("$UnitName" + "_http_json_call_node.js")');
  Lines.Add('$callTest       = Join-Path $GenDir ("$UnitName" + "_http_json_call_main_test___.js")');
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
  Lines.Add('Write-Ok "All four generated JS files present."');
  Lines.Add('');
end;

procedure EmitInstall(Lines: TPascalStringList);
begin
  Lines.Add('$nodeModules = Join-Path $GenDir "node_modules"');
  Lines.Add('if (-not (Test-Path -LiteralPath $nodeModules)) {');
  Lines.Add('    New-Item -ItemType Directory -Path $nodeModules | Out-Null');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$targetPkg = Join-Path $nodeModules "lingofuse-js"');
  Lines.Add('if ($Force -and (Test-Path -LiteralPath $targetPkg)) {');
  Lines.Add('    Write-Info "Force: removing existing lingofuse-js"');
  Lines.Add('    Remove-Item -LiteralPath $targetPkg -Recurse -Force');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $targetPkg)) {');
  Lines.Add('    Write-Info "Installing lingofuse-js from $JsLibDir ..."');
  Lines.Add('    Push-Location $GenDir');
  Lines.Add('    try {');
  Lines.Add('        & npm install --no-save --no-audit --no-fund --loglevel=error $JsLibDir');
  Lines.Add('        if ($LASTEXITCODE -ne 0) {');
  Lines.Add('            Write-Fail "npm install failed (exit $LASTEXITCODE)."');
  Lines.Add('            exit 1');
  Lines.Add('        }');
  Lines.Add('    } finally {');
  Lines.Add('        Pop-Location');
  Lines.Add('    }');
  Lines.Add('    if (-not (Test-Path -LiteralPath $targetPkg)) {');
  Lines.Add('        Write-Fail "npm install returned success but lingofuse-js is still missing."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "lingofuse-js installed."');
  Lines.Add('} else {');
  Lines.Add('    Write-Ok "lingofuse-js already installed (use -Force to reinstall)."');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$smokeCmd = "node .\$UnitName" + "_http_json_service_main_test___.js --smoke"');
  Lines.Add('$callCmd  = "node .\$UnitName" + "_http_json_call_main_test___.js"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Ready. Next steps:" -ForegroundColor Green');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  Smoke test (no bridge needed):" -ForegroundColor Cyan');
  Lines.Add('Write-Host "      cd `"$GenDir`""');
  Lines.Add('Write-Host "      $smokeCmd"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  End-to-end call test (bridge + service required):" -ForegroundColor Cyan');
  Lines.Add('Write-Host "      cd `"$GenDir`""');
  Lines.Add('Write-Host "      $callCmd"');
  Lines.Add('Write-Host ""');
  Lines.Add('');
  Lines.Add('if ($RunSmoke) {');
  Lines.Add('    Write-Info "Running service-side smoke test ..."');
  Lines.Add('    Push-Location $GenDir');
  Lines.Add('    try {');
  Lines.Add('        & node ("$UnitName" + "_http_json_service_main_test___.js") --smoke');
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

function GenerateJsTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;
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
    EmitInstall(Lines);
    Result := Lines;
    Log('Generated setup_js_tests.ps1');
  finally
    if Result <> Lines then Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'nodejs', 'Node.js HTTP/JSON test setup script',
    asBoth, akBuildScript,
    'setup_js_tests.ps1', True,
    @GenerateJsTestSetupScript);

end.
