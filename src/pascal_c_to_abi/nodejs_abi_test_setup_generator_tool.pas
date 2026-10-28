unit nodejs_abi_test_setup_generator_tool;

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

function GenerateNodejsTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[nodejs_abi_test_setup_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[nodejs_abi_test_setup_generator] %s', [PFormat(Fmt, Args)]);
end;

function GenerateNodejsTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;
  if Model.UnitName.Len = 0 then
  begin
    Log('UnitName is empty');
    Exit;
  end;

  Log('Generating setup_node_tests.ps1');

  Lines := TPascalStringList.Create;
  try
    Lines.Add('#Requires -Version 5.1');
    Lines.Add('');
    Lines.Add('[CmdletBinding()]');
    Lines.Add('param(');
    Lines.Add('    [string]$LingoFuseJs = "",');
    Lines.Add('    [string]$GenDir = "",');
    Lines.Add('    [string]$UnitName = "",');
    Lines.Add('    [switch]$Force,');
    Lines.Add('    [switch]$RunSmoke,');
    Lines.Add('    [switch]$Help');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('$ErrorActionPreference = "Stop"');
    Lines.Add('');
    Lines.Add('if ($args -contains "--help") { $Help = $true }');
    Lines.Add('if ($LingoFuseJs -eq "--help") { $Help = $true; $LingoFuseJs = "" }');
    Lines.Add('if ($GenDir -eq "--help") { $Help = $true; $GenDir = "" }');
    Lines.Add('if ($UnitName -eq "--help") { $Help = $true; $UnitName = "" }');
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
    Lines.Add('if ($Help) {');
    Lines.Add('    Write-Host "Usage: setup_node_tests.ps1 -LingoFuseJs <path> [options]"');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "One-shot Node.js test environment bootstrap for LingoFuse ABI generated code."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Required:"');
    Lines.Add('    Write-Host "  -LingoFuseJs <path>  Path to the lingofuse-js source directory."');
    Lines.Add('    Write-Host "                       Example: D:\CoreLibrary\LingoFuse\js"');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Optional:"');
    Lines.Add('    Write-Host "  -GenDir <path>       Generated project directory. Default: script directory."');
    Lines.Add('    Write-Host "  -UnitName <name>     Source unit name. Default: auto-detect."');
    Lines.Add('    Write-Host "  -RunSmoke            Run service + call test after setup."');
    Lines.Add('    Write-Host "  -Help                Show this help."');
    Lines.Add('    exit 0');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('if (-not $LingoFuseJs) {');
    Lines.Add('    Write-Fail "-LingoFuseJs is required."');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('if (-not (Test-Path -LiteralPath $LingoFuseJs)) {');
    Lines.Add('    Write-Fail "LingoFuseJs not found: $LingoFuseJs"');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('$LingoFuseJs = (Resolve-Path -LiteralPath $LingoFuseJs).Path');
    Lines.Add('');
    Lines.Add('$lfPkg = Join-Path $LingoFuseJs "package.json"');
    Lines.Add('if (-not (Test-Path -LiteralPath $lfPkg)) {');
    Lines.Add('    Write-Fail "Missing package.json in LingoFuseJs: $lfPkg"');
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
    Lines.Add('Write-Info "LingoFuseJs : $LingoFuseJs"');
    Lines.Add('Write-Info "GenDir      : $GenDir"');
    Lines.Add('');
    Lines.Add('$nodeCmd = Get-Command node -ErrorAction SilentlyContinue');
    Lines.Add('if ($null -eq $nodeCmd) {');
    Lines.Add('    Write-Fail "node is not on PATH. Install Node.js 18+."');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('$nodeExe = $nodeCmd.Source');
    Lines.Add('$nodeVer = (& node --version 2>&1) -join ""');
    Lines.Add('Write-Ok "node $nodeVer"');
    Lines.Add('');
    Lines.Add('$npmCmd = Get-Command npm -ErrorAction SilentlyContinue');
    Lines.Add('if ($null -eq $npmCmd) {');
    Lines.Add('    Write-Fail "npm is not on PATH."');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('$npmVer = (& npm --version 2>&1) -join ""');
    Lines.Add('Write-Ok "npm $npmVer"');
    Lines.Add('');
    Lines.Add('$abiExt = ""');
    Lines.Add('');
    Lines.Add('if (-not $UnitName) {');
    Lines.Add('    $cand = Get-ChildItem -LiteralPath $GenDir -File -Filter "*_abi_service.js" -ErrorAction SilentlyContinue | Select-Object -First 1');
    Lines.Add('    if ($null -ne $cand) {');
    Lines.Add('        $UnitName = $cand.Name -replace ' + #39 + '_abi_service\.js$' + #39 + ', ' + #39 + #39);
    Lines.Add('        $abiExt = ' + #39 + '.js' + #39);
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('if (-not $UnitName) {');
    Lines.Add('    $cand = Get-ChildItem -LiteralPath $GenDir -File -Filter "*_abi_service.cjs" -ErrorAction SilentlyContinue | Select-Object -First 1');
    Lines.Add('    if ($null -ne $cand) {');
    Lines.Add('        $UnitName = $cand.Name -replace ' + #39 + '_abi_service\.cjs$' + #39 + ', ' + #39 + #39);
    Lines.Add('        $abiExt = ' + #39 + '.cjs' + #39);
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('if (-not $UnitName) {');
    Lines.Add('    Write-Fail "Cannot auto-detect UnitName. Pass -UnitName explicitly."');
    Lines.Add('    Write-Fail ""');
    Lines.Add('    Write-Fail "Files in $GenDir matching *_abi_service*:"');
    Lines.Add('    $cands = @(Get-ChildItem -LiteralPath $GenDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*_abi_service*" })');
    Lines.Add('    if ($cands.Count -eq 0) {');
    Lines.Add('        Write-Fail "  (none)"');
    Lines.Add('        Write-Fail "Run code_decl_to_abi --lang nodejs <source> $GenDir first."');
    Lines.Add('    } else {');
    Lines.Add('        foreach ($c in $cands) { Write-Fail "  $($c.Name)" }');
    Lines.Add('    }');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('if ($abiExt -eq ' + #39 + #39 + ') { $abiExt = ' + #39 + '.js' + #39 + ' }');
    Lines.Add('if ($abiExt -eq ' + #39 + '.cjs' + #39 + ') {');
    Lines.Add('    Write-Warn "Detected legacy .cjs artifacts; the current generator emits .js files."');
    Lines.Add('    Write-Warn "Re-run code_decl_to_abi to upgrade."');
    Lines.Add('}');
    Lines.Add('Write-Ok "UnitName $UnitName (ext $abiExt)"');
    Lines.Add('');
    Lines.Add('$required = @(');
    Lines.Add('    "${UnitName}_abi_service$abiExt",');
    Lines.Add('    "${UnitName}_abi_call$abiExt",');
    Lines.Add('    "${UnitName}_abi_service_test$abiExt",');
    Lines.Add('    "${UnitName}_abi_call_test$abiExt"');
    Lines.Add(')');
    Lines.Add('$missing = @()');
    Lines.Add('foreach ($f in $required) {');
    Lines.Add('    $p = Join-Path $GenDir $f');
    Lines.Add('    if (-not (Test-Path -LiteralPath $p)) { $missing += $f }');
    Lines.Add('}');
    Lines.Add('if ($missing.Count -gt 0) {');
    Lines.Add('    Write-Fail "Missing generated files in $GenDir :"');
    Lines.Add('    foreach ($m in $missing) { Write-Host "        $m" }');
    Lines.Add('    Write-Fail "Run code_decl_to_abi --lang nodejs first."');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('Write-Ok "Generated files present"');
    Lines.Add('');
    Lines.Add('$lfKoffi = Join-Path $LingoFuseJs "node_modules/koffi"');
    Lines.Add('if (-not (Test-Path -LiteralPath $lfKoffi)) {');
    Lines.Add('    Write-Info "lingofuse-js/node_modules/koffi is missing; running npm install in LingoFuseJs"');
    Lines.Add('    Push-Location $LingoFuseJs');
    Lines.Add('    try {');
    Lines.Add('        & npm install');
    Lines.Add('        if ($LASTEXITCODE -ne 0) { Write-Fail "npm install failed in $LingoFuseJs"; exit 1 }');
    Lines.Add('    } finally {');
    Lines.Add('        Pop-Location');
    Lines.Add('    }');
    Lines.Add('    if (-not (Test-Path -LiteralPath $lfKoffi)) {');
    Lines.Add('        Write-Fail "lingofuse-js/node_modules/koffi still missing after npm install."');
    Lines.Add('        exit 1');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('Write-Ok "lingofuse-js dependencies present"');
    Lines.Add('');
    Lines.Add('$pkgPath = Join-Path $GenDir "package.json"');
    Lines.Add('$lfNormalized = $LingoFuseJs.Replace("\", "/")');
    Lines.Add('$pkgName = "${UnitName}_abi".ToLower()');
    Lines.Add('$pkgContent = @"');
    Lines.Add('{');
    Lines.Add('  "name": "$pkgName",');
    Lines.Add('  "version": "0.1.0",');
    Lines.Add('  "type": "commonjs",');
    Lines.Add('  "dependencies": {');
    Lines.Add('    "lingofuse-js": "file:$lfNormalized"');
    Lines.Add('  }');
    Lines.Add('}');
    Lines.Add('"@');
    Lines.Add('Write-TextFileNoBom -Path $pkgPath -Content $pkgContent');
    Lines.Add('Write-Ok "package.json written (lingofuse-js -> $lfNormalized)"');
    Lines.Add('');
    Lines.Add('Write-Info "Running npm install in $GenDir ..."');
    Lines.Add('Push-Location $GenDir');
    Lines.Add('try {');
    Lines.Add('    & npm install');
    Lines.Add('    if ($LASTEXITCODE -ne 0) { Write-Fail "npm install failed in $GenDir"; exit 1 }');
    Lines.Add('} finally {');
    Lines.Add('    Pop-Location');
    Lines.Add('}');
    Lines.Add('Write-Ok "npm install done"');
    Lines.Add('');
    Lines.Add('Write-Info "Syntax checking generated files ..."');
    Lines.Add('$checkFailed = $false');
    Lines.Add('foreach ($f in $required) {');
    Lines.Add('    $p = Join-Path $GenDir $f');
    Lines.Add('    & node --check $p');
    Lines.Add('    if ($LASTEXITCODE -ne 0) {');
    Lines.Add('        Write-Fail "syntax check failed: $f"');
    Lines.Add('        $checkFailed = $true');
    Lines.Add('    } else {');
    Lines.Add('        Write-Ok "syntax ok: $f"');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('if ($checkFailed) {');
    Lines.Add('    Write-Fail "one or more files failed the syntax check"');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('if ($RunSmoke) {');
    Lines.Add('    $svcFile = "${UnitName}_abi_service_test$abiExt"');
    Lines.Add('    $callFile = "${UnitName}_abi_call_test$abiExt"');
    Lines.Add('    Write-Info "Starting $svcFile in the background ..."');
    Lines.Add('    $svcLog = Join-Path $GenDir "smoke_service.out.log"');
    Lines.Add('    $svcErr = Join-Path $GenDir "smoke_service.err.log"');
    Lines.Add('    $svcProc = Start-Process -FilePath $nodeExe -ArgumentList @($svcFile) -WorkingDirectory $GenDir -PassThru -NoNewWindow -RedirectStandardOutput $svcLog -RedirectStandardError $svcErr');
    Lines.Add('    Start-Sleep -Seconds 3');
    Lines.Add('    Push-Location $GenDir');
    Lines.Add('    try {');
    Lines.Add('        Write-Info "Running $callFile ..."');
    Lines.Add('        & node $callFile');
    Lines.Add('        $rc = $LASTEXITCODE');
    Lines.Add('    } finally {');
    Lines.Add('        Pop-Location');
    Lines.Add('    }');
    Lines.Add('    Start-Sleep -Milliseconds 500');
    Lines.Add('    if ($null -ne $svcProc -and -not $svcProc.HasExited) {');
    Lines.Add('        Stop-Process -Id $svcProc.Id -Force -ErrorAction SilentlyContinue');
    Lines.Add('    }');
    Lines.Add('    if ($rc -ne 0) {');
    Lines.Add('        Write-Fail "call_test failed (exit $rc)."');
    Lines.Add('        Write-Fail "        service log: $svcLog"');
    Lines.Add('        Write-Fail "        service err: $svcErr"');
    Lines.Add('        exit 1');
    Lines.Add('    }');
    Lines.Add('    Write-Ok "smoke test passed"');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('Write-Host ""');
    Lines.Add('Write-Host "Environment is ready." -ForegroundColor Green');
    Lines.Add('Write-Host ""');
    Lines.Add('Write-Host "  Terminal 1 (service):" -ForegroundColor Cyan');
    Lines.Add('Write-Host "      cd `"$GenDir`""');
    Lines.Add('Write-Host "      node ${UnitName}_abi_service_test$abiExt"');
    Lines.Add('Write-Host ""');
    Lines.Add('Write-Host "  Terminal 2 (call):" -ForegroundColor Cyan');
    Lines.Add('Write-Host "      cd `"$GenDir`""');
    Lines.Add('Write-Host "      node ${UnitName}_abi_call_test$abiExt"');
    Lines.Add('Write-Host ""');
    Lines.Add('Write-Host "The call test exits with code 0 when all tests pass, 2 otherwise." -ForegroundColor DarkGray');
    Lines.Add('Write-Host ""');
    Lines.Add('exit 0');

    Result := Lines;
    Log(PFormat('Generated %d lines for setup_node_tests.ps1', [Lines.Count]));
  finally
  end;
end;

initialization

  RegisterGenerator(
    'nodejs',
    'setup_node_tests.ps1',
    gkPs1,
    'Node.js ABI test environment setup script',
    @GenerateNodejsTestSetupScript);

end.
