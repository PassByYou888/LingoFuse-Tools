unit http_erlang_abi_test_setup_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core, Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  code_decl_to_json_abi_registry;

function GenerateErlangTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

const
  CH_SQ = #39;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_erlang_abi_test_setup_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[http_erlang_abi_test_setup_generator] %s', [PFormat(Fmt, Args)]);
end;

procedure EmitSetupHeader(Lines: TPascalStringList);
begin
  Lines.Add('#Requires -Version 5.1');
  Lines.Add('');
  Lines.Add('[CmdletBinding()]');
  Lines.Add('param(');
  Lines.Add('    [string]$ErlangBindingDir = "",');
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

procedure EmitSetupHelp(Lines: TPascalStringList);
begin
  Lines.Add('if ($Help) {');
  Lines.Add('    $help = @' + CH_SQ);
  Lines.Add('Usage: setup_erlang_tests.ps1 -ErlangBindingDir <path> [options]');
  Lines.Add('');
  Lines.Add('Prepares the Erlang test environment for the generated HTTP/JSON binding.');
  Lines.Add('It copies beams and the NIF, then compiles the generated modules.');
  Lines.Add('It does NOT run any test and does NOT need bridge.py.');
  Lines.Add('');
  Lines.Add('Required:');
  Lines.Add('  -ErlangBindingDir <path>');
  Lines.Add('        Path to the LingoFuse Erlang binding directory.');
  Lines.Add('        Must contain:');
  Lines.Add('            _build\default\lib\lingofuse\ebin\lingofuse*.beam');
  Lines.Add('            priv\lingofuse_nif.dll');
  Lines.Add('');
  Lines.Add('Optional:');
  Lines.Add('  -GenDir <path>');
  Lines.Add('        Directory containing the four generated files.');
  Lines.Add('        Default: the directory containing this script.');
  Lines.Add('');
  Lines.Add('  -UnitName <name>');
  Lines.Add('        Source unit name, without extension.');
  Lines.Add('        Default: auto-detected from <name>_http_json_service.erl.');
  Lines.Add('');
  Lines.Add('  -Force');
  Lines.Add('        Overwrite existing ebin\ and priv\ contents.');
  Lines.Add('');
  Lines.Add('  -RunSmoke');
  Lines.Add('        After preparing, immediately run the smoke test:');
  Lines.Add('            escript .\<Unit>_http_json_service_main_test___.escript --smoke');
  Lines.Add('');
  Lines.Add('  -Help');
  Lines.Add('        Show this help text and exit.');
  Lines.Add('');
  Lines.Add('Example:');
  Lines.Add('  .\setup_erlang_tests.ps1 `');
  Lines.Add('      -ErlangBindingDir D:\CoreLibrary\LingoFuse\erlang -RunSmoke');
  Lines.Add('');
  Lines.Add('Exit codes:');
  Lines.Add('  0   success (or -Help was requested)');
  Lines.Add('  1   argument validation failed, missing file, or compile failed');
  Lines.Add(CH_SQ + '@');
  Lines.Add('    Write-Host $help');
  Lines.Add('    exit 0');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupRequired(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $ErlangBindingDir) {');
  Lines.Add('    Write-Fail "-ErlangBindingDir is required."');
  Lines.Add('    Write-Host "        Run ' + CH_SQ + 'setup_erlang_tests.ps1 -Help' + CH_SQ + ' for usage."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupPaths(Lines: TPascalStringList);
begin
  Lines.Add('$ErlangBindingDir = (Resolve-Path -LiteralPath $ErlangBindingDir).Path');
  Lines.Add('');
  Lines.Add('$LfEbin = Join-Path $ErlangBindingDir "_build\default\lib\lingofuse\ebin"');
  Lines.Add('$LfPriv = Join-Path $ErlangBindingDir "priv"');
  Lines.Add('$NifDll = Join-Path $LfPriv "lingofuse_nif.dll"');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $LfEbin)) {');
  Lines.Add('    Write-Fail "-ErlangBindingDir does not look like the LingoFuse Erlang binding."');
  Lines.Add('    Write-Fail "            Missing: $LfEbin"');
  Lines.Add('    Write-Fail "            Build it first:  cd $ErlangBindingDir ; .\build.ps1"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$lfBeams = @(Get-ChildItem -LiteralPath $LfEbin -Filter "lingofuse*.beam" -File -ErrorAction SilentlyContinue)');
  Lines.Add('if ($lfBeams.Count -eq 0) {');
  Lines.Add('    Write-Fail "No lingofuse*.beam under $LfEbin"');
  Lines.Add('    Write-Fail "            Build it first:  cd $ErlangBindingDir ; .\build.ps1"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $NifDll)) {');
  Lines.Add('    Write-Fail "Missing NIF: $NifDll"');
  Lines.Add('    Write-Fail "            Build it first:  cd $ErlangBindingDir ; .\build.ps1"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $GenDir) { $GenDir = $PSScriptRoot }');
  Lines.Add('$GenDir = (Resolve-Path -LiteralPath $GenDir).Path');
  Lines.Add('');
  Lines.Add('Write-Info "ErlangBindingDir : $ErlangBindingDir"');
  Lines.Add('Write-Info "GenDir           : $GenDir"');
  Lines.Add('');
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    $candidate = Get-ChildItem -LiteralPath $GenDir -Filter "*_http_json_service.erl" -File | Select-Object -First 1');
  Lines.Add('    if ($null -eq $candidate) {');
  Lines.Add('        Write-Fail "Cannot detect UnitName (no *_http_json_service.erl in $GenDir)."');
  Lines.Add('        Write-Fail "            Pass -UnitName explicitly."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    $UnitName = $candidate.Name -replace ' + CH_SQ + '_http_json_service\.erl$' + CH_SQ + ', ' + CH_SQ + CH_SQ);
  Lines.Add('}');
  Lines.Add('Write-Info "UnitName         : $UnitName"');
  Lines.Add('');
  Lines.Add('$serviceErl    = Join-Path $GenDir ("$UnitName" + "_http_json_service.erl")');
  Lines.Add('$callErl       = Join-Path $GenDir ("$UnitName" + "_http_json_call.erl")');
  Lines.Add('$serviceTestEs = Join-Path $GenDir ("$UnitName" + "_http_json_service_main_test___.escript")');
  Lines.Add('$callTestEs    = Join-Path $GenDir ("$UnitName" + "_http_json_call_main_test___.escript")');
  Lines.Add('');
  Lines.Add('$missing = @()');
  Lines.Add('foreach ($p in @($serviceErl, $callErl, $serviceTestEs, $callTestEs)) {');
  Lines.Add('    if (-not (Test-Path -LiteralPath $p)) { $missing += $p }');
  Lines.Add('}');
  Lines.Add('if ($missing.Count -gt 0) {');
  Lines.Add('    Write-Fail "Missing generated files:"');
  Lines.Add('    foreach ($m in $missing) { Write-Host "        $m" }');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "All four generated files present."');
  Lines.Add('');
  Lines.Add('$erlcCmd = Get-Command erlc -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $erlcCmd) {');
  Lines.Add('    Write-Fail "erlc is not on PATH."');
  Lines.Add('    Write-Fail "            Install Erlang/OTP and add its bin directory to PATH."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupPrepare(Lines: TPascalStringList);
begin
  Lines.Add('$EbinDir = Join-Path $GenDir "ebin"');
  Lines.Add('$PrivDir = Join-Path $GenDir "priv"');
  Lines.Add('');
  Lines.Add('if ($Force) {');
  Lines.Add('    if (Test-Path -LiteralPath $EbinDir) { Remove-Item -LiteralPath $EbinDir -Recurse -Force }');
  Lines.Add('    if (Test-Path -LiteralPath $PrivDir) { Remove-Item -LiteralPath $PrivDir -Recurse -Force }');
  Lines.Add('}');
  Lines.Add('New-Item -ItemType Directory -Force -Path $EbinDir | Out-Null');
  Lines.Add('New-Item -ItemType Directory -Force -Path $PrivDir | Out-Null');
  Lines.Add('');
  Lines.Add('$beamSources = @(Get-ChildItem -LiteralPath $LfEbin -Filter "lingofuse*.beam" -File)');
  Lines.Add('foreach ($b in $beamSources) {');
  Lines.Add('    Copy-Item -LiteralPath $b.FullName -Destination $EbinDir -Force');
  Lines.Add('}');
  Lines.Add('Write-Ok "Copied $($beamSources.Count) lingofuse beam(s) to $EbinDir"');
  Lines.Add('');
  Lines.Add('Copy-Item -LiteralPath $NifDll -Destination $PrivDir -Force');
  Lines.Add('Write-Ok "Copied lingofuse_nif.dll to $PrivDir"');
  Lines.Add('');
  Lines.Add('Write-Info "Compiling generated modules..."');
  Lines.Add('Push-Location $GenDir');
  Lines.Add('try {');
  Lines.Add('    & erlc -o $EbinDir $serviceErl $callErl');
  Lines.Add('    if ($LASTEXITCODE -ne 0) {');
  Lines.Add('        Write-Fail "erlc failed (exit $LASTEXITCODE)"');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('} finally {');
  Lines.Add('    Pop-Location');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$svcBeam  = Join-Path $EbinDir ("$UnitName" + "_http_json_service.beam")');
  Lines.Add('$callBeam = Join-Path $EbinDir ("$UnitName" + "_http_json_call.beam")');
  Lines.Add('if (-not (Test-Path -LiteralPath $svcBeam))  { Write-Fail "Not produced: $svcBeam";  exit 1 }');
  Lines.Add('if (-not (Test-Path -LiteralPath $callBeam)) { Write-Fail "Not produced: $callBeam"; exit 1 }');
  Lines.Add('Write-Ok "Compiled service and call modules."');
  Lines.Add('');
end;

procedure EmitSetupSummary(Lines: TPascalStringList);
begin
  Lines.Add('$endpoint = "ipc:" + $UnitName + "_http_json"');
  Lines.Add('');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "================================================================" -ForegroundColor Green');
  Lines.Add('Write-Host "  Environment ready." -ForegroundColor Green');
  Lines.Add('Write-Host "================================================================" -ForegroundColor Green');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  ebin\ : $EbinDir"');
  Lines.Add('Write-Host "  priv\ : $PrivDir"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  1) Smoke test (in-process; no bridge, no network):" -ForegroundColor Cyan');
  Lines.Add('Write-Host "       escript .\$UnitName`_http_json_service_main_test___.escript --smoke"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  2) End-to-end (three terminals):" -ForegroundColor Cyan');
  Lines.Add('Write-Host "       [T1] escript .\$UnitName`_http_json_service_main_test___.escript"');
  Lines.Add('Write-Host "       [T2] python bridge.py --endpoint $endpoint --port 8081 --no-precheck"');
  Lines.Add('Write-Host "       [T3] escript .\$UnitName`_http_json_call_main_test___.escript"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  Exit code 0 means success." -ForegroundColor Gray');
  Lines.Add('Write-Host ""');
  Lines.Add('');
end;

procedure EmitSetupRunSmoke(Lines: TPascalStringList);
begin
  Lines.Add('if ($RunSmoke) {');
  Lines.Add('    Write-Info "Running smoke test..."');
  Lines.Add('    Push-Location $GenDir');
  Lines.Add('    try {');
  Lines.Add('        & escript ("$UnitName" + "_http_json_service_main_test___.escript") --smoke');
  Lines.Add('        $smokeCode = $LASTEXITCODE');
  Lines.Add('    } finally {');
  Lines.Add('        Pop-Location');
  Lines.Add('    }');
  Lines.Add('    if ($smokeCode -ne 0) {');
  Lines.Add('        Write-Fail "smoke test failed (exit $smokeCode)"');
  Lines.Add('        exit $smokeCode');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "smoke test passed."');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('exit 0');
end;

function GenerateErlangTestSetupScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
  UnitName: TP_String;
begin
  Result := nil;
  if Model = nil then
  begin
    Log('GenerateErlangTestSetupScript: Model is nil');
    Exit;
  end;

  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log('GenerateErlangTestSetupScript: UnitName is empty');
    Exit;
  end;

  Lines := TPascalStringList.Create;
  try
    EmitSetupHeader(Lines);
    EmitSetupHelp(Lines);
    EmitSetupRequired(Lines);
    EmitSetupPaths(Lines);
    EmitSetupPrepare(Lines);
    EmitSetupSummary(Lines);
    EmitSetupRunSmoke(Lines);

    Result := Lines;
    Log(PFormat('Generated setup_erlang_tests.ps1: %d lines (unit=%s).',
      [Lines.Count, UnitName.Text]));
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization
  RegisterCodeGenEntry(
    'erlang', 'Erlang test setup script',
    asBoth, akBuildScript,
    'setup_erlang_tests.ps1', True,
    @GenerateErlangTestSetupScript);

end.
