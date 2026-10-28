unit dart_abi_test_setup_generator_tool;

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

function GenerateDartTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[dart_abi_test_setup_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[dart_abi_test_setup_generator] %s', [PFormat(Fmt, Args)]);
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function GenerateDartTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('UnitName is empty');
    Exit;
  end;

  NormalizedUnit := MakeApiName(UnitName);

  Log(PFormat('Generating setup_dart_tests.ps1 for unit "%s"', [UnitName.Text]));

  Lines := TPascalStringList.Create;
  try
    Lines.Add('#Requires -Version 5.1');
    Lines.Add('');
    Lines.Add('[CmdletBinding()]');
    Lines.Add('param(');
    Lines.Add('    [string]$LingoFuseDart = ' + #39 + #39 + ',');
    Lines.Add('    [string]$GenDir = ' + #39 + #39 + ',');
    Lines.Add('    [string]$UnitName = ' + #39 + #39 + ',');
    Lines.Add('    [switch]$Force,');
    Lines.Add('    [switch]$RunSmoke,');
    Lines.Add('    [switch]$Help');
    Lines.Add(')');
    Lines.Add('');
    Lines.Add('$ErrorActionPreference = ' + #39 + 'Stop' + #39);
    Lines.Add('');
    Lines.Add('if ($args -contains "--help") { $Help = $true }');
    Lines.Add('if ($LingoFuseDart -eq "--help") { $Help = $true; $LingoFuseDart = "" }');
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
    Lines.Add('function Find-File-Upward {');
    Lines.Add('    param(');
    Lines.Add('        [Parameter(Mandatory=$true)][string]$StartDir,');
    Lines.Add('        [Parameter(Mandatory=$true)][string]$FileName,');
    Lines.Add('        [int]$MaxLevels = 8');
    Lines.Add('    )');
    Lines.Add('    $cur = (Resolve-Path -LiteralPath $StartDir).Path');
    Lines.Add('    for ($i = 0; $i -lt $MaxLevels; $i++) {');
    Lines.Add('        $candidate = Join-Path $cur $FileName');
    Lines.Add('        if (Test-Path -LiteralPath $candidate) {');
    Lines.Add('            return (Resolve-Path -LiteralPath $candidate).Path');
    Lines.Add('        }');
    Lines.Add('        $parent = Split-Path -Parent $cur');
    Lines.Add('        if (-not $parent -or $parent -eq $cur) { break }');
    Lines.Add('        $cur = $parent');
    Lines.Add('    }');
    Lines.Add('    return $null');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('function Find-LingoFuseDartUpward {');
    Lines.Add('    param(');
    Lines.Add('        [Parameter(Mandatory=$true)][string]$StartDir,');
    Lines.Add('        [int]$MaxLevels = 8');
    Lines.Add('    )');
    Lines.Add('    $cur = (Resolve-Path -LiteralPath $StartDir).Path');
    Lines.Add('    for ($i = 0; $i -lt $MaxLevels; $i++) {');
    Lines.Add('        $candidates = @(');
    Lines.Add('            (Join-Path $cur ' + #39 + 'lib/lingofuse.dart' + #39 + '),');
    Lines.Add('            (Join-Path $cur ' + #39 + 'dart/lib/lingofuse.dart' + #39 + ')');
    Lines.Add('        )');
    Lines.Add('        foreach ($c in $candidates) {');
    Lines.Add('            if (Test-Path -LiteralPath $c) {');
    Lines.Add('                return (Split-Path -Parent (Split-Path -Parent $c))');
    Lines.Add('            }');
    Lines.Add('        }');
    Lines.Add('        $parent = Split-Path -Parent $cur');
    Lines.Add('        if (-not $parent -or $parent -eq $cur) { break }');
    Lines.Add('        $cur = $parent');
    Lines.Add('    }');
    Lines.Add('    return $null');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('if ($Help) {');
    Lines.Add('    Write-Host ' + #39 + 'Usage: setup_dart_tests.ps1 -LingoFuseDart <path> [options]' + #39);
    Lines.Add('    Write-Host ' + #39 + 'One-shot Dart ABI test environment bootstrap for LingoFuse.' + #39);
    Lines.Add('    Write-Host ' + #39 + '' + #39);
    Lines.Add('    Write-Host ' + #39 + 'Required:' + #39);
    Lines.Add('    Write-Host ' + #39 + '  -LingoFuseDart <path>  Path to the lingofuse Dart package root.' + #39);
    Lines.Add('    Write-Host ' + #39 + '                         Example: D:\CoreLibrary\LingoFuse\dart' + #39);
    Lines.Add('    Write-Host ' + #39 + '                         Auto-detected from -GenDir if omitted.' + #39);
    Lines.Add('    Write-Host ' + #39 + '' + #39);
    Lines.Add('    Write-Host ' + #39 + 'Optional:' + #39);
    Lines.Add('    Write-Host ' + #39 + '  -GenDir <path>         Generated project directory. Default: script directory.' + #39);
    Lines.Add('    Write-Host ' + #39 + '  -UnitName <name>       Source unit name. Auto-detected from *_abi_service_test.dart.' + #39);
    Lines.Add('    Write-Host ' + #39 + '  -Force                 Overwrite existing pubspec.yaml and bridge DLL.' + #39);
    Lines.Add('    Write-Host ' + #39 + '  -RunSmoke              Run service + call test after setup.' + #39);
    Lines.Add('    Write-Host ' + #39 + '  -Help                  Show this help.' + #39);
    Lines.Add('    Write-Host ' + #39 + '' + #39);
    Lines.Add('    Write-Host ' + #39 + 'Exit codes: 0 = environment ready, 1 = setup failure.' + #39);
    Lines.Add('    exit 0');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('Write-Info ' + #39 + 'Preconditions' + #39);
    Lines.Add('');
    Lines.Add('if (-not $GenDir) { $GenDir = $PSScriptRoot }');
    Lines.Add('if (-not (Test-Path -LiteralPath $GenDir)) {');
    Lines.Add('    Write-Fail (' + #39 + 'GenDir not found: ' + #39 + ' + $GenDir)');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('$GenDir = (Resolve-Path -LiteralPath $GenDir).Path');
    Lines.Add('Write-Ok (' + #39 + 'GenDir: ' + #39 + ' + $GenDir)');
    Lines.Add('');
    Lines.Add('if (-not $LingoFuseDart) {');
    Lines.Add('    if ($env:LINGOFUSE_DART_DIR -and (Test-Path -LiteralPath $env:LINGOFUSE_DART_DIR)) {');
    Lines.Add('        $LingoFuseDart = $env:LINGOFUSE_DART_DIR');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('if (-not $LingoFuseDart) {');
    Lines.Add('    $auto = Find-LingoFuseDartUpward -StartDir $GenDir');
    Lines.Add('    if ($auto) { $LingoFuseDart = $auto }');
    Lines.Add('}');
    Lines.Add('if (-not $LingoFuseDart) {');
    Lines.Add('    Write-Fail ' + #39 + 'Cannot auto-detect the lingofuse Dart package.' + #39);
    Lines.Add('    Write-Fail ' + #39 + 'Pass -LingoFuseDart <path> explicitly.' + #39);
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('if (-not (Test-Path -LiteralPath $LingoFuseDart)) {');
    Lines.Add('    Write-Fail (' + #39 + 'LingoFuseDart not found: ' + #39 + ' + $LingoFuseDart)');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('$LingoFuseDart = (Resolve-Path -LiteralPath $LingoFuseDart).Path');
    Lines.Add('Write-Ok (' + #39 + 'LingoFuseDart: ' + #39 + ' + $LingoFuseDart)');
    Lines.Add('');
    Lines.Add('$lfPubspec = Join-Path $LingoFuseDart ' + #39 + 'pubspec.yaml' + #39);
    Lines.Add('if (-not (Test-Path -LiteralPath $lfPubspec)) {');
    Lines.Add('    Write-Fail (' + #39 + 'Missing pubspec.yaml in LingoFuseDart: ' + #39 + ' + $lfPubspec)');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('$lfLib = Join-Path $LingoFuseDart ' + #39 + 'lib/lingofuse.dart' + #39);
    Lines.Add('if (-not (Test-Path -LiteralPath $lfLib)) {');
    Lines.Add('    Write-Fail (' + #39 + 'Missing lib/lingofuse.dart in LingoFuseDart: ' + #39 + ' + $lfLib)');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('Write-Ok (' + #39 + 'lingofuse package found: ' + #39 + ' + $LingoFuseDart)');
    Lines.Add('');
    Lines.Add('$dartCmd = Get-Command dart -ErrorAction SilentlyContinue');
    Lines.Add('if (-not $dartCmd) {');
    Lines.Add('    Write-Fail ' + #39 + 'dart not found on PATH.' + #39);
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('$dartExe = $dartCmd.Source');
    Lines.Add('$dartVer = (& dart --version 2>&1) -join ' + #39 + ' ' + #39);
    Lines.Add('Write-Ok (' + #39 + 'dart: ' + #39 + ' + $dartVer)');
    Lines.Add('');
    Lines.Add('Write-Info ' + #39 + 'Checking generated files' + #39);
    Lines.Add('');
    Lines.Add('if (-not $UnitName) {');
    Lines.Add('    $candidates = @(Get-ChildItem -LiteralPath $GenDir -File -Filter ' + #39 + '*_abi_service_test.dart' + #39 + ' -ErrorAction SilentlyContinue)');
    Lines.Add('    if ($candidates.Count -eq 0) {');
    Lines.Add('        Write-Fail (' + #39 + 'no *_abi_service_test.dart in ' + #39 + ' + $GenDir)');
    Lines.Add('        Write-Fail ' + #39 + 'Run code_decl_to_abi --lang dart first.' + #39);
    Lines.Add('        exit 1');
    Lines.Add('    }');
    Lines.Add('    if ($candidates.Count -gt 1) {');
    Lines.Add('        Write-Fail (' + #39 + 'multiple *_abi_service_test.dart in ' + #39 + ' + $GenDir + ' + #39 + '; pass -UnitName explicitly' + #39 + ')');
    Lines.Add('        exit 1');
    Lines.Add('    }');
    Lines.Add('    $UnitName = $candidates[0].Name -replace ' + #39 + '_abi_service_test\.dart$' + #39 + ', ' + #39 + #39);
    Lines.Add('}');
    Lines.Add('Write-Ok (' + #39 + 'UnitName: ' + #39 + ' + $UnitName)');
    Lines.Add('');
    Lines.Add('$svcFile       = "${UnitName}_abi_service.dart"');
    Lines.Add('$callFile      = "${UnitName}_abi_call.dart"');
    Lines.Add('$svcTestFile   = "${UnitName}_abi_service_test.dart"');
    Lines.Add('$callTestFile  = "${UnitName}_abi_call_test.dart"');
    Lines.Add('');
    Lines.Add('$required = @($svcFile, $callFile, $svcTestFile, $callTestFile)');
    Lines.Add('$missing = @()');
    Lines.Add('foreach ($f in $required) {');
    Lines.Add('    $p = Join-Path $GenDir $f');
    Lines.Add('    if (-not (Test-Path -LiteralPath $p)) { $missing += $f }');
    Lines.Add('}');
    Lines.Add('if ($missing.Count -gt 0) {');
    Lines.Add('    Write-Fail (' + #39 + 'Missing generated files in ' + #39 + ' + $GenDir + ' + #39 + ':' + #39 + ')');
    Lines.Add('    foreach ($m in $missing) { Write-Host "        $m" }');
    Lines.Add('    Write-Fail ' + #39 + 'Run code_decl_to_abi --lang dart first.' + #39);
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('Write-Ok ' + #39 + '4 generated .dart files present' + #39);
    Lines.Add('');
    Lines.Add('Write-Info ' + #39 + 'Locating lf_dart_bridge.dll' + #39);
    Lines.Add('');
    Lines.Add('$bridgeSrc = $null');
    Lines.Add('$bridgeCandidates = @(');
    Lines.Add('    (Join-Path $LingoFuseDart ' + #39 + 'bridge/lf_dart_bridge.dll' + #39 + '),');
    Lines.Add('    (Join-Path $LingoFuseDart ' + #39 + 'lf_dart_bridge.dll' + #39 + ')');
    Lines.Add(')');
    Lines.Add('if ($env:LINGOFUSE_BRIDGE_DLL -and (Test-Path -LiteralPath $env:LINGOFUSE_BRIDGE_DLL)) {');
    Lines.Add('    $bridgeSrc = $env:LINGOFUSE_BRIDGE_DLL');
    Lines.Add('}');
    Lines.Add('if (-not $bridgeSrc) {');
    Lines.Add('    foreach ($c in $bridgeCandidates) {');
    Lines.Add('        if (Test-Path -LiteralPath $c) { $bridgeSrc = $c; break }');
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('if (-not $bridgeSrc) {');
    Lines.Add('    $found = Find-File-Upward -StartDir $LingoFuseDart -FileName ' + #39 + 'lf_dart_bridge.dll' + #39);
    Lines.Add('    if ($found) { $bridgeSrc = $found }');
    Lines.Add('}');
    Lines.Add('if (-not $bridgeSrc) {');
    Lines.Add('    Write-Fail ' + #39 + 'lf_dart_bridge.dll not found.' + #39);
    Lines.Add('    Write-Fail (' + #39 + '    Build it first: cd ' + #39 + ' + $LingoFuseDart + ' + #39 + '\bridge; .\build.ps1' + #39 + ')');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('$bridgeSrc = (Resolve-Path -LiteralPath $bridgeSrc).Path');
    Lines.Add('Write-Ok (' + #39 + 'bridge DLL: ' + #39 + ' + $bridgeSrc)');
    Lines.Add('');
    Lines.Add('Write-Info ' + #39 + 'Locating LingoFuse64.dll (runtime)' + #39);
    Lines.Add('');
    Lines.Add('$lf64 = Get-ChildItem -Path $env:PATH -Filter ' + #39 + 'LingoFuse64.dll' + #39 + ' -ErrorAction SilentlyContinue | Select-Object -First 1');
    Lines.Add('if ($lf64) {');
    Lines.Add('    Write-Ok (' + #39 + 'LingoFuse64.dll on PATH: ' + #39 + ' + $lf64.FullName)');
    Lines.Add('} else {');
    Lines.Add('    Write-Warn ' + #39 + 'LingoFuse64.dll not found on PATH.' + #39);
    Lines.Add('    Write-Warn ' + #39 + 'Add D:\CoreLibrary\LingoFuse\Binary (or the equivalent) to PATH.' + #39);
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('Write-Info ' + #39 + 'Writing pubspec.yaml' + #39);
    Lines.Add('');
    Lines.Add('$pkgName = $UnitName.ToLower() -replace ' + #39 + '[^a-z0-9_]' + #39 + ', ' + #39 + '_' + #39);
    Lines.Add('if ($pkgName -match ' + #39 + '^[0-9]' + #39 + ') { $pkgName = ' + #39 + 'p_' + #39 + ' + $pkgName }');
    Lines.Add('if (-not $pkgName) { $pkgName = ' + #39 + 'dart_abi_tests' + #39 + ' }');
    Lines.Add('$pkgName = $pkgName + ' + #39 + '_abi_tests' + #39);
    Lines.Add('$normalizedLingofuse = $LingoFuseDart.Replace([string][char]92, [string][char]47)');
    Lines.Add('$pkgPath = Join-Path $GenDir ' + #39 + 'pubspec.yaml' + #39);
    Lines.Add('$pkgExists = Test-Path -LiteralPath $pkgPath');
    Lines.Add('if ($pkgExists -and -not $Force) {');
    Lines.Add('    Write-Ok ' + #39 + 'pubspec.yaml already exists (use -Force to overwrite)' + #39);
    Lines.Add('} else {');
    Lines.Add('    $pkgContent = @"');
    Lines.Add('name: $pkgName');
    Lines.Add('description: ABI tests for $UnitName');
    Lines.Add('version: 0.0.1');
    Lines.Add('environment:');
    Lines.Add('  sdk: ">=3.0.0 <4.0.0"');
    Lines.Add('dependencies:');
    Lines.Add('  lingofuse:');
    Lines.Add('    path: "$normalizedLingofuse"');
    Lines.Add('"@');
    Lines.Add('    Write-TextFileNoBom -Path $pkgPath -Content $pkgContent');
    Lines.Add('    Write-Ok (' + #39 + 'pubspec.yaml written: ' + #39 + ' + $pkgName)');
    Lines.Add('    Write-Info (' + #39 + 'lingofuse path: ' + #39 + ' + $normalizedLingofuse)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('Write-Info ' + #39 + 'Running dart pub get in GenDir' + #39);
    Lines.Add('');
    Lines.Add('Push-Location $GenDir');
    Lines.Add('try {');
    Lines.Add('    & dart pub get');
    Lines.Add('    if ($LASTEXITCODE -ne 0) {');
    Lines.Add('        Write-Fail ' + #39 + 'dart pub get failed.' + #39);
    Lines.Add('        exit 1');
    Lines.Add('    }');
    Lines.Add('} finally {');
    Lines.Add('    Pop-Location');
    Lines.Add('}');
    Lines.Add('Write-Ok ' + #39 + 'dart pub get done' + #39);
    Lines.Add('');
    Lines.Add('Write-Info ' + #39 + 'Copying lf_dart_bridge.dll into GenDir' + #39);
    Lines.Add('');
    Lines.Add('$bridgeDst = Join-Path $GenDir ' + #39 + 'lf_dart_bridge.dll' + #39);
    Lines.Add('$needCopy = $true');
    Lines.Add('if ((Test-Path -LiteralPath $bridgeDst) -and -not $Force) {');
    Lines.Add('    $dstItem = Get-Item -LiteralPath $bridgeDst');
    Lines.Add('    $srcItem = Get-Item -LiteralPath $bridgeSrc');
    Lines.Add('    if ($dstItem.Length -eq $srcItem.Length) {');
    Lines.Add('        $needCopy = $false');
    Lines.Add('        Write-Ok ' + #39 + 'bridge DLL already copied (use -Force to overwrite)' + #39);
    Lines.Add('    }');
    Lines.Add('}');
    Lines.Add('if ($needCopy) {');
    Lines.Add('    Copy-Item -LiteralPath $bridgeSrc -Destination $bridgeDst -Force');
    Lines.Add('    Write-Ok (' + #39 + 'bridge DLL copied to: ' + #39 + ' + $bridgeDst)');
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('Write-Info ' + #39 + 'Running dart analyze' + #39);
    Lines.Add('');
    Lines.Add('Push-Location $GenDir');
    Lines.Add('try {');
    Lines.Add('    & dart analyze --no-fatal-warnings $svcFile $callFile $svcTestFile $callTestFile');
    Lines.Add('    $analyzeExit = $LASTEXITCODE');
    Lines.Add('} finally {');
    Lines.Add('    Pop-Location');
    Lines.Add('}');
    Lines.Add('if ($analyzeExit -ge 2) {');
    Lines.Add('    Write-Fail (' + #39 + 'dart analyze failed (exit ' + #39 + ' + $analyzeExit + ' + #39 + ')' + #39 + ')');
    Lines.Add('    exit 1');
    Lines.Add('}');
    Lines.Add('Write-Ok ' + #39 + 'dart analyze passed' + #39);
    Lines.Add('');
    Lines.Add('if ($RunSmoke) {');
    Lines.Add('    Write-Info ' + #39 + 'Running smoke test (service + call)' + #39);
    Lines.Add('    $svcLog = Join-Path $GenDir ' + #39 + 'smoke_service.out.log' + #39);
    Lines.Add('    $svcErr = Join-Path $GenDir ' + #39 + 'smoke_service.err.log' + #39);
    Lines.Add('    if (Test-Path -LiteralPath $svcLog) { Remove-Item -LiteralPath $svcLog -Force }');
    Lines.Add('    if (Test-Path -LiteralPath $svcErr) { Remove-Item -LiteralPath $svcErr -Force }');
    Lines.Add('    $svcProc = Start-Process -FilePath $dartExe -ArgumentList @($svcTestFile) -WorkingDirectory $GenDir -PassThru -NoNewWindow -RedirectStandardOutput $svcLog -RedirectStandardError $svcErr');
    Lines.Add('    Start-Sleep -Seconds 4');
    Lines.Add('    Push-Location $GenDir');
    Lines.Add('    try {');
    Lines.Add('        & dart $callTestFile');
    Lines.Add('        $rc = $LASTEXITCODE');
    Lines.Add('    } finally {');
    Lines.Add('        Pop-Location');
    Lines.Add('    }');
    Lines.Add('    Start-Sleep -Milliseconds 500');
    Lines.Add('    if ($null -ne $svcProc -and -not $svcProc.HasExited) {');
    Lines.Add('        Stop-Process -Id $svcProc.Id -Force -ErrorAction SilentlyContinue');
    Lines.Add('    }');
    Lines.Add('    if ($rc -ne 0) {');
    Lines.Add('        Write-Fail (' + #39 + 'call test failed (exit ' + #39 + ' + $rc + ' + #39 + ')' + #39 + ')');
    Lines.Add('        Write-Fail (' + #39 + '        service log: ' + #39 + ' + $svcLog)');
    Lines.Add('        Write-Fail (' + #39 + '        service err: ' + #39 + ' + $svcErr)');
    Lines.Add('        exit 1');
    Lines.Add('    }');
    Lines.Add('    Write-Ok ' + #39 + 'smoke test passed' + #39);
    Lines.Add('}');
    Lines.Add('');
    Lines.Add('Write-Host ' + #39 + #39);
    Lines.Add('Write-Host ' + #39 + 'Environment is ready.' + #39 + ' -ForegroundColor Green');
    Lines.Add('Write-Host ' + #39 + #39);
    Lines.Add('Write-Host ' + #39 + '  Terminal 1 (service):' + #39 + ' -ForegroundColor Cyan');
    Lines.Add('Write-Host "      cd `"$GenDir`""');
    Lines.Add('Write-Host "      dart run $svcTestFile"');
    Lines.Add('Write-Host ' + #39 + #39);
    Lines.Add('Write-Host ' + #39 + '  Terminal 2 (call):' + #39 + ' -ForegroundColor Cyan');
    Lines.Add('Write-Host "      cd `"$GenDir`""');
    Lines.Add('Write-Host "      dart run $callTestFile"');
    Lines.Add('Write-Host ' + #39 + #39);
    Lines.Add('Write-Host ' + #39 + '  Terminal 1 runs the service. Press Enter (or Ctrl+C) to shut it down.' + #39);
    Lines.Add('Write-Host ' + #39 + '  Terminal 2 runs the call test; exits 0 on success or 2 on failure.' + #39);
    Lines.Add('Write-Host ' + #39 + #39);
    Lines.Add('Write-Host ' + #39 + '  Make sure the LingoFuse binary directory is on PATH:' + #39);
    Lines.Add('Write-Host ' + #39 + '      (e.g., D:\CoreLibrary\LingoFuse\Binary)' + #39);
    Lines.Add('Write-Host ' + #39 + #39);
    Lines.Add('Write-Host ' + #39 + '  For cross-language tests:' + #39);
    Lines.Add('Write-Host ' + #39 + '      Run any language service (Pascal / C++ / Rust / ...) on:' + #39);
    Lines.Add('Write-Host "          ipc:${UnitName}_abi"');
    Lines.Add('Write-Host ' + #39 + '      Then point this Dart call test at it.' + #39);
    Lines.Add('Write-Host ' + #39 + #39);
    Lines.Add('exit 0');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated %d lines for setup_dart_tests.ps1', [Lines.Count]));
  finally
  end;
end;

initialization

  RegisterGenerator(
    'dart',
    'setup_dart_tests.ps1',
    gkPs1,
    'Dart ABI test environment setup script',
    @GenerateDartTestSetupScript);

end.
