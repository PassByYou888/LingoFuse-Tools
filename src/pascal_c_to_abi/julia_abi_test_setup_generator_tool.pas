unit julia_abi_test_setup_generator_tool;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\..\zCore\src\Z.Define.inc}

interface

uses
  Z.Core,
  Z.PascalStrings, Z.UPascalStrings,
  Z.Status, Z.Json, Z.UnicodeMixedLib, Z.ListEngine,
  Z.Pascal_Func_Model,
  Z.Parsing, code_decl_to_abi_registry;

function GenerateABIProjectToml(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABIRunTests(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABISetupScript(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABIRunServiceScript(Model: TPascal_Func_Model): TPascalStringList;
function GenerateABIRunCallScript(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

const
  C_LingoFuse_UUID = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';
  C_Test_UUID      = '8dfed614-e22c-5e08-85e1-65c5234f0b40';

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[julia_abi_test_setup_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[julia_abi_test_setup_generator] %s', [PFormat(Fmt, Args)]);
end;

function MakeApiName(const FuncName: TP_String): TP_String;
begin
  Result := FuncName.ReplaceChar(#32#9'./\@', '_');
end;

function JuliaStrLit(const S: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := '"';
  for i := 1 to S.Len do
  begin
    c := S[i];
    if c = '"' then
    begin
      Result.Append('\');
      Result.Append('"');
    end
    else if c = '\' then
    begin
      Result.Append('\');
      Result.Append('\');
    end
    else if c = #10 then
    begin
      Result.Append('\');
      Result.Append('n');
    end
    else if c = #13 then
    begin
      Result.Append('\');
      Result.Append('r');
    end
    else if c = #9 then
    begin
      Result.Append('\');
      Result.Append('t');
    end
    else
      Result.Append(c);
  end;
  Result.Append('"');
end;

function ByteToHex2(b: Byte): TP_String;
begin
  Result := IntToHex(b, 2);
end;

function MakeJuliaUUID(const UnitName: TP_String): TP_String;
var
  nameBytes: TBytes;
  nameStr: SystemString;
  md5: TMD5;
begin
  nameStr := 'lingofuse.abi.' + UnitName.Text;
  nameBytes := TEncoding.UTF8.GetBytes(nameStr);
  md5 := umlMD5(PByte(@nameBytes[0]), Length(nameBytes));
  md5[6] := (md5[6] and $0F) or $50;
  md5[8] := (md5[8] and $3F) or $80;
  Result :=
    ByteToHex2(md5[0]) + ByteToHex2(md5[1]) + ByteToHex2(md5[2]) + ByteToHex2(md5[3]) + '-' +
    ByteToHex2(md5[4]) + ByteToHex2(md5[5]) + '-' +
    ByteToHex2(md5[6]) + ByteToHex2(md5[7]) + '-' +
    ByteToHex2(md5[8]) + ByteToHex2(md5[9]) + '-' +
    ByteToHex2(md5[10]) + ByteToHex2(md5[11]) + ByteToHex2(md5[12]) + ByteToHex2(md5[13]) + ByteToHex2(md5[14]) + ByteToHex2(md5[15]);
end;

function GenerateABIProjectToml(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, NsName, Uuid: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  Uuid := MakeJuliaUUID(UnitName);

  Lines := TPascalStringList.Create;
  try
    Lines.Add('name = ' + JuliaStrLit(NsName));
    Lines.Add('uuid = ' + JuliaStrLit(Uuid));
    Lines.Add('version = "0.1.0"');
    Lines.Add('');
    Lines.Add('[deps]');
    Lines.Add('LingoFuse = ' + JuliaStrLit(C_LingoFuse_UUID));
    Lines.Add('');
    Lines.Add('[extras]');
    Lines.Add('Test = ' + JuliaStrLit(C_Test_UUID));
    Lines.Add('');
    Lines.Add('[targets]');
    Lines.Add('test = ["Test"]');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated Project.toml: %d lines', [Lines.Count]));
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

function GenerateABIRunTests(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, NormalizedUnit, NsName, SvcFile, CallFile: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then Exit;

  NormalizedUnit := MakeApiName(UnitName);
  NsName := NormalizedUnit + '_abi';
  SvcFile := NormalizedUnit + '_abi_service_test.jl';
  CallFile := NormalizedUnit + '_abi_call_test.jl';

  Lines := TPascalStringList.Create;
  try
    Lines.Add('if Threads.nthreads() < 2');
    Lines.Add('    error("This test suite requires --threads=2 (got $(Threads.nthreads())).")');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('using Test');
    Lines.Add('');
    Lines.Add('const HERE = @__DIR__');
    Lines.Add('const SERVICE_TEST = joinpath(HERE, ' + JuliaStrLit(SvcFile) + ')');
    Lines.Add('const CALL_TEST = joinpath(HERE, ' + JuliaStrLit(CallFile) + ')');
    Lines.Add('');
    Lines.Add('if !isfile(SERVICE_TEST)');
    Lines.Add('    error("missing " * SERVICE_TEST)');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('@testset ' + JuliaStrLit(NsName + ' integration') + ' begin');
    Lines.Add('    println("[TEST] spawning service_test subprocess: " * SERVICE_TEST)');
    Lines.Add('    proc = run(`$(Base.julia_cmd()) --threads=2 $(SERVICE_TEST)`; wait=true)');
    Lines.Add('    @test proc.exitcode == 0');
    Lines.Add('end');
    Lines.Add('');
    Lines.Add('if isfile(CALL_TEST)');
    Lines.Add('    println()');
    Lines.Add('    println("[INFO] cross-process verification:")');
    Lines.Add('    println("[INFO]   terminal A: julia --threads=2 " * SERVICE_TEST * " --serve-only")');
    Lines.Add('    println("[INFO]   terminal B: julia --threads=2 " * CALL_TEST)');
    Lines.Add('end');
    Lines.Add('');

    Result := Lines;
    Log(PFormat('Generated runtests.jl: %d lines', [Lines.Count]));
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

procedure EmitSetupHeader(Lines: TPascalStringList);
begin
  Lines.Add('#Requires -Version 5.1');
  Lines.Add('');
  Lines.Add('[CmdletBinding()]');
  Lines.Add('param(');
  Lines.Add('    [string]$LingoFuseJulia = "",');
  Lines.Add('    [string]$LingoFuseLib   = "",');
  Lines.Add('    [string]$GenDir         = "",');
  Lines.Add('    [string]$UnitName       = "",');
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

procedure EmitSetupHelp(Lines: TPascalStringList);
begin
  Lines.Add('if ($Help) {');
  Lines.Add('    Write-Host "setup_julia_tests.ps1"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "One-shot Julia test environment bootstrap for LingoFuse ABI generated code."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "This script ONLY prepares the environment. It does NOT run any test."');
  Lines.Add('    Write-Host "To run the tests, use run_julia_service.ps1 and run_julia_call.ps1 in two terminals."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "What it does:"');
  Lines.Add('    Write-Host "  1. Validate the LingoFuse Julia package directory."');
  Lines.Add('    Write-Host "  2. Validate the generated .jl files in GenDir."');
  Lines.Add('    Write-Host "  3. Create <GenDir>/.julia_clean_build/ with:"');
  Lines.Add('    Write-Host "         Project.toml, runtests.jl, 4 generated .jl files, and the runtime library."');
  Lines.Add('    Write-Host "  4. Run Pkg.develop to install the LingoFuse dependency into the clean project."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Required:"');
  Lines.Add('    Write-Host "  -LingoFuseJulia <path>"');
  Lines.Add('    Write-Host "        Path to the LingoFuse Julia package directory (contains Project.toml and src/LingoFuse.jl)."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Optional:"');
  Lines.Add('    Write-Host "  -LingoFuseLib <path>"');
  Lines.Add('    Write-Host "        Path to LingoFuse64.dll / liblingofuse.so / liblingofuse.dylib (file or directory)."');
  Lines.Add('    Write-Host "        If omitted, the script searches <GenDir>, <LingoFuseJulia>/../Binary, and PATH."');
  Lines.Add('    Write-Host "  -GenDir <path>     Generated project directory. Default: this script directory."');
  Lines.Add('    Write-Host "  -UnitName <name>   Source unit name. Default: auto-detect from *_abi_service.jl."');
  Lines.Add('    Write-Host "  -Force             Recreate the clean build directory from scratch."');
  Lines.Add('    Write-Host "  -Clean             Delete the clean build directory after a successful setup."');
  Lines.Add('    Write-Host "  -Help              Show this help."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Examples:"');
  Lines.Add('    Write-Host "  .\setup_julia_tests.ps1 -LingoFuseJulia D:\CoreLibrary\LingoFuse\julia"');
  Lines.Add('    Write-Host "  .\setup_julia_tests.ps1 -LingoFuseJulia D:\CoreLibrary\LingoFuse\julia -Force"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "After setup succeeds, run in two terminals:"');
  Lines.Add('    Write-Host "  Terminal A: .\run_julia_service.ps1"');
  Lines.Add('    Write-Host "  Terminal B: .\run_julia_call.ps1   (after A prints [READY])"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Exit codes:"');
  Lines.Add('    Write-Host "  0   success"');
  Lines.Add('    Write-Host "  1   validation failed or missing tool"');
  Lines.Add('    exit 0');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupValidateArgs(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $LingoFuseJulia) {');
  Lines.Add('    Write-Fail "-LingoFuseJulia is required."');
  Lines.Add('    Write-Fail "        Run setup_julia_tests.ps1 -Help for usage."');
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
  Lines.Add('Write-Info "GenDir         : $GenDir"');
  Lines.Add('');
end;

procedure EmitSetupToolCheck(Lines: TPascalStringList);
begin
  Lines.Add('$juliaCmd = Get-Command julia -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $juliaCmd) {');
  Lines.Add('    Write-Fail "julia is not on PATH."');
  Lines.Add('    Write-Fail "        Install Julia 1.9+ from https://julialang.org/downloads/"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$juliaExe = $juliaCmd.Source');
  Lines.Add('$juliaVerOut = ((& $juliaExe --version 2>&1) | Out-String).Trim()');
  Lines.Add('Write-Ok "julia: $juliaVerOut"');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $LingoFuseJulia)) {');
  Lines.Add('    Write-Fail "LingoFuseJulia not found: $LingoFuseJulia"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$LingoFuseJulia = (Resolve-Path -LiteralPath $LingoFuseJulia).Path');
  Lines.Add('$lfProj = Join-Path $LingoFuseJulia "Project.toml"');
  Lines.Add('$lfSrc  = Join-Path $LingoFuseJulia "src/LingoFuse.jl"');
  Lines.Add('if (-not (Test-Path -LiteralPath $lfProj)) {');
  Lines.Add('    Write-Fail "Missing Project.toml in LingoFuseJulia: $lfProj"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('if (-not (Test-Path -LiteralPath $lfSrc)) {');
  Lines.Add('    Write-Fail "Missing src/LingoFuse.jl in LingoFuseJulia: $lfSrc"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "LingoFuse Julia package: $LingoFuseJulia"');
  Lines.Add('');
end;

procedure EmitSetupDetectUnitName(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    $cand = Get-ChildItem -LiteralPath $GenDir -File -Filter "*_abi_service.jl" -ErrorAction SilentlyContinue | Select-Object -First 1');
  Lines.Add('    if ($null -ne $cand) {');
  Lines.Add('        $UnitName = $cand.Name -replace ' + #39 + '_abi_service\.jl$' + #39 + ', ' + #39 + #39);
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    Write-Fail "Cannot auto-detect UnitName (no *_abi_service.jl in $GenDir)."');
  Lines.Add('    Write-Fail "        Pass -UnitName explicitly."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Info "UnitName       : $UnitName"');
  Lines.Add('');
end;

procedure EmitSetupCheckGeneratedFiles(Lines: TPascalStringList);
begin
  Lines.Add('$svcJl        = Join-Path $GenDir "${UnitName}_abi_service.jl"');
  Lines.Add('$callJl       = Join-Path $GenDir "${UnitName}_abi_call.jl"');
  Lines.Add('$svcTestJl    = Join-Path $GenDir "${UnitName}_abi_service_test.jl"');
  Lines.Add('$callTestJl   = Join-Path $GenDir "${UnitName}_abi_call_test.jl"');
  Lines.Add('$projSrc      = Join-Path $GenDir "Project.toml"');
  Lines.Add('$runtestsSrc  = Join-Path $GenDir "runtests.jl"');
  Lines.Add('');
  Lines.Add('$missing = @()');
  Lines.Add('foreach ($p in @($svcJl, $callJl, $svcTestJl, $callTestJl, $projSrc, $runtestsSrc)) {');
  Lines.Add('    if (-not (Test-Path -LiteralPath $p)) { $missing += $p }');
  Lines.Add('}');
  Lines.Add('if ($missing.Count -gt 0) {');
  Lines.Add('    Write-Fail "Missing generated Julia files:"');
  Lines.Add('    foreach ($m in $missing) { Write-Host "        $m" }');
  Lines.Add('    Write-Fail "Run code_decl_to_abi first to emit the .jl files."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "All generated Julia files present."');
  Lines.Add('');
end;

procedure EmitSetupDetectLib(Lines: TPascalStringList);
begin
  Lines.Add('$libFound = $null');
  Lines.Add('$libNames = @("LingoFuse64.dll", "LingoFuse32.dll", "liblingofuse.so", "liblingofuse.dylib")');
  Lines.Add('');
  Lines.Add('if ($LingoFuseLib) {');
  Lines.Add('    if (-not (Test-Path -LiteralPath $LingoFuseLib)) {');
  Lines.Add('        Write-Fail "LingoFuseLib not found: $LingoFuseLib"');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    if (Test-Path -LiteralPath $LingoFuseLib -PathType Container) {');
  Lines.Add('        foreach ($n in $libNames) {');
  Lines.Add('            $c = Join-Path $LingoFuseLib $n');
  Lines.Add('            if (Test-Path -LiteralPath $c) { $libFound = $c; break }');
  Lines.Add('        }');
  Lines.Add('    } else {');
  Lines.Add('        $libFound = (Resolve-Path -LiteralPath $LingoFuseLib).Path');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $libFound) {');
  Lines.Add('    $searchDirs = @($GenDir)');
  Lines.Add('    $lfParent = Split-Path $LingoFuseJulia -Parent');
  Lines.Add('    if ($lfParent) {');
  Lines.Add('        $searchDirs += (Join-Path $lfParent "Binary")');
  Lines.Add('        $searchDirs += $lfParent');
  Lines.Add('    }');
  Lines.Add('    foreach ($d in $searchDirs) {');
  Lines.Add('        if (-not (Test-Path -LiteralPath $d)) { continue }');
  Lines.Add('        foreach ($n in $libNames) {');
  Lines.Add('            $c = Join-Path $d $n');
  Lines.Add('            if (Test-Path -LiteralPath $c) { $libFound = $c; break }');
  Lines.Add('        }');
  Lines.Add('        if ($libFound) { break }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $libFound) {');
  Lines.Add('    $pathEntries = ($env:PATH -split ' + #39 + ';' + #39 + ') | Where-Object { $_ -ne ' + #39 + #39 + ' }');
  Lines.Add('    foreach ($d in $pathEntries) {');
  Lines.Add('        foreach ($n in $libNames) {');
  Lines.Add('            $c = Join-Path $d $n');
  Lines.Add('            if (Test-Path -LiteralPath $c) { $libFound = $c; break }');
  Lines.Add('        }');
  Lines.Add('        if ($libFound) { break }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $libFound) {');
  Lines.Add('    Write-Fail "No LingoFuse runtime library found (.dll / .so / .dylib)."');
  Lines.Add('    Write-Fail "        Use -LingoFuseLib <path> to specify one explicitly."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "Runtime library: $libFound"');
  Lines.Add('');
end;

procedure EmitSetupCreateCleanDir(Lines: TPascalStringList);
begin
  Lines.Add('$cleanDir = Join-Path $GenDir ".julia_clean_build"');
  Lines.Add('');
  Lines.Add('if ($Force -and (Test-Path -LiteralPath $cleanDir)) {');
  Lines.Add('    Write-Info "Force: removing existing clean directory."');
  Lines.Add('    Remove-Item -LiteralPath $cleanDir -Recurse -Force');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not (Test-Path -LiteralPath $cleanDir)) {');
  Lines.Add('    New-Item -ItemType Directory -Path $cleanDir -Force | Out-Null');
  Lines.Add('    Write-Ok "Created clean directory: $cleanDir"');
  Lines.Add('} else {');
  Lines.Add('    Write-Info "Reusing clean directory: $cleanDir"');
  Lines.Add('    Get-ChildItem -LiteralPath $cleanDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupCopyFiles(Lines: TPascalStringList);
begin
  Lines.Add('function Get-LingoFuseUUID {');
  Lines.Add('    param([string]$UnitName)');
  Lines.Add('    $md5 = [System.Security.Cryptography.MD5]::Create()');
  Lines.Add('    try {');
  Lines.Add('        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes("lingofuse.abi.$UnitName")');
  Lines.Add('        $hash = $md5.ComputeHash($inputBytes)');
  Lines.Add('    } finally {');
  Lines.Add('        $md5.Dispose()');
  Lines.Add('    }');
  Lines.Add('    $hash[6] = ($hash[6] -band 0x0F) -bor 0x50');
  Lines.Add('    $hash[8] = ($hash[8] -band 0x3F) -bor 0x80');
  Lines.Add('    return (');
  Lines.Add('        $hash[0].ToString("x2") + $hash[1].ToString("x2") + $hash[2].ToString("x2") + $hash[3].ToString("x2") + "-" +');
  Lines.Add('        $hash[4].ToString("x2") + $hash[5].ToString("x2") + "-" +');
  Lines.Add('        $hash[6].ToString("x2") + $hash[7].ToString("x2") + "-" +');
  Lines.Add('        $hash[8].ToString("x2") + $hash[9].ToString("x2") + "-" +');
  Lines.Add('        $hash[10].ToString("x2") + $hash[11].ToString("x2") + $hash[12].ToString("x2") + $hash[13].ToString("x2") + $hash[14].ToString("x2") + $hash[15].ToString("x2")');
  Lines.Add('    )');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$dstProj = Join-Path $cleanDir "Project.toml"');
  Lines.Add('Copy-Item -LiteralPath $projSrc -Destination $dstProj -Force');
  Lines.Add('$projText = Get-Content -LiteralPath $dstProj -Raw');
  Lines.Add('if ($projText -match ' + #39 + 'uuid\s*=\s*"([^"]+)"' + #39 + ') {');
  Lines.Add('    $existingUuid = $matches[1]');
  Lines.Add('    $uuidPattern = ' + #39 + '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' + #39);
  Lines.Add('    if ($existingUuid -notmatch $uuidPattern) {');
  Lines.Add('        $newUuid = Get-LingoFuseUUID -UnitName $UnitName');
  Lines.Add('        $projText = $projText -replace ' + #39 + 'uuid\s*=\s*"[^"]+"' + #39 + ', "uuid = `"$newUuid`""');
  Lines.Add('        Write-TextFileNoBom -Path $dstProj -Content $projText');
  Lines.Add('        Write-Warn "Fixed malformed UUID in Project.toml"');
  Lines.Add('        Write-Warn "    old: $existingUuid"');
  Lines.Add('        Write-Warn "    new: $newUuid"');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Copy-Item -LiteralPath $runtestsSrc -Destination (Join-Path $cleanDir "runtests.jl") -Force');
  Lines.Add('Write-Ok "Copied Project.toml (UUID verified) and runtests.jl"');
  Lines.Add('');
  Lines.Add('foreach ($src in @($svcJl, $callJl, $svcTestJl, $callTestJl)) {');
  Lines.Add('    Copy-Item -LiteralPath $src -Destination (Join-Path $cleanDir (Split-Path $src -Leaf)) -Force');
  Lines.Add('}');
  Lines.Add('Write-Ok "Copied 4 generated .jl files into clean directory"');
  Lines.Add('');
  Lines.Add('$libLeaf = Split-Path $libFound -Leaf');
  Lines.Add('Copy-Item -LiteralPath $libFound -Destination (Join-Path $cleanDir $libLeaf) -Force');
  Lines.Add('Write-Ok "Copied runtime library: $libLeaf"');
  Lines.Add('');
end;

procedure EmitSetupInstallDeps(Lines: TPascalStringList);
begin
  Lines.Add('Push-Location $cleanDir');
  Lines.Add('try {');
  Lines.Add('    Write-Info "Installing LingoFuse dependency (Pkg.develop)..."');
  Lines.Add('    $juliaPathFwd = $LingoFuseJulia -replace ' + #39 + '\\' + #39 + ', ' + #39 + '/' + #39);
  Lines.Add('    $developExpr = "using Pkg; Pkg.develop(path=" + [char]34 + $juliaPathFwd + [char]34 + ")"');
  Lines.Add('    & $juliaExe "--project=." "-e" $developExpr');
  Lines.Add('    $rc = $LASTEXITCODE');
  Lines.Add('    if ($rc -ne 0) {');
  Lines.Add('        Write-Fail "Pkg.develop failed (exit $rc)."');
  Lines.Add('        Write-Fail "        Common cause: no network access to the Julia registry."');
  Lines.Add('        Write-Fail "        Pre-install JSON3 manually: julia -e ""using Pkg; Pkg.add(' + #39 + 'JSON3' + #39 + ')"""');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "LingoFuse dependency installed."');
  Lines.Add('} finally {');
  Lines.Add('    Pop-Location');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupNextSteps(Lines: TPascalStringList);
begin
  Lines.Add('$libLeaf = Split-Path $libFound -Leaf');
  Lines.Add('');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Environment is ready." -ForegroundColor Green');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Clean directory: $cleanDir" -ForegroundColor Cyan');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Run the test in two separate terminals (matching the C++/Pascal/Java workflow):" -ForegroundColor Cyan');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  Terminal A (service):" -ForegroundColor Yellow');
  Lines.Add('Write-Host "      cd `"$GenDir`""');
  Lines.Add('Write-Host "      .\run_julia_service.ps1"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  Terminal B (call test, after A prints [READY]):" -ForegroundColor Yellow');
  Lines.Add('Write-Host "      cd `"$GenDir`""');
  Lines.Add('Write-Host "      .\run_julia_call.ps1"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "IMPORTANT: Do NOT press Ctrl+C in Terminal A until Terminal B has finished." -ForegroundColor Magenta');
  Lines.Add('Write-Host "           The service must remain running while the call test executes." -ForegroundColor Magenta');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "The service keeps running until you press Ctrl+C." -ForegroundColor DarkGray');
  Lines.Add('Write-Host "The call test exits 0 when all checks PASS or SKIP; 2 if any FAIL." -ForegroundColor DarkGray');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "If loader.jl cannot find the runtime library from PATH," -ForegroundColor DarkGray');
  Lines.Add('Write-Host "set the override in the test terminal before running:" -ForegroundColor DarkGray');
  Lines.Add('Write-Host "    `$env:LINGOFUSE_LIBRARY = `"$cleanDir\$libLeaf`"" -ForegroundColor DarkGray');
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

function GenerateABISetupScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;

  Lines := TPascalStringList.Create;
  try
    EmitSetupHeader(Lines);
    EmitSetupHelp(Lines);
    EmitSetupValidateArgs(Lines);
    EmitSetupToolCheck(Lines);
    EmitSetupDetectUnitName(Lines);
    EmitSetupCheckGeneratedFiles(Lines);
    EmitSetupDetectLib(Lines);
    EmitSetupCreateCleanDir(Lines);
    EmitSetupCopyFiles(Lines);
    EmitSetupInstallDeps(Lines);
    EmitSetupNextSteps(Lines);
    Result := Lines;
    Log(PFormat('Generated setup_julia_tests.ps1: %d lines', [Lines.Count]));
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

procedure EmitRunHeader(Lines: TPascalStringList);
begin
  Lines.Add('#Requires -Version 5.1');
  Lines.Add('');
  Lines.Add('[CmdletBinding()]');
  Lines.Add('param(');
  Lines.Add('    [string]$GenDir = "",');
  Lines.Add('    [int]$Threads   = 2,');
  Lines.Add('    [switch]$Help');
  Lines.Add(')');
  Lines.Add('');
  Lines.Add('$ErrorActionPreference = "Stop"');
  Lines.Add('');
end;

procedure EmitRunCommonResolve(Lines: TPascalStringList;
  const MainSuffix: TP_String; const Args_ : TP_String);
begin
  Lines.Add('if ($Threads -lt 2) {');
  Lines.Add('    Write-Host "[fail] Threads must be >= 2 (got $Threads)." -ForegroundColor Red');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $GenDir) { $GenDir = $PSScriptRoot }');
  Lines.Add('if (-not (Test-Path -LiteralPath $GenDir)) {');
  Lines.Add('    Write-Host "[fail] GenDir not found: $GenDir" -ForegroundColor Red');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$GenDir = (Resolve-Path -LiteralPath $GenDir).Path');
  Lines.Add('');
  Lines.Add('$cleanDir = Join-Path $GenDir ".julia_clean_build"');
  Lines.Add('if (-not (Test-Path -LiteralPath $cleanDir)) {');
  Lines.Add('    Write-Host "[fail] Clean directory not found: $cleanDir" -ForegroundColor Red');
  Lines.Add('    Write-Host "[fail] Run setup_julia_tests.ps1 first." -ForegroundColor Red');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$manifest = Join-Path $cleanDir "Manifest.toml"');
  Lines.Add('if (-not (Test-Path -LiteralPath $manifest)) {');
  Lines.Add('    Write-Host "[fail] Manifest.toml not found: $manifest" -ForegroundColor Red');
  Lines.Add('    Write-Host "[fail] Run setup_julia_tests.ps1 first to install dependencies." -ForegroundColor Red');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$cand = Get-ChildItem -LiteralPath $cleanDir -File -Filter "*' + MainSuffix.Text + '.jl" -ErrorAction SilentlyContinue | Select-Object -First 1');
  Lines.Add('if ($null -eq $cand) {');
  Lines.Add('    Write-Host "[fail] Cannot find *' + MainSuffix.Text + '.jl in $cleanDir" -ForegroundColor Red');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$juliaCmd = Get-Command julia -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $juliaCmd) {');
  Lines.Add('    Write-Host "[fail] julia is not on PATH." -ForegroundColor Red');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('Write-Host "[info] CleanDir : $cleanDir" -ForegroundColor Cyan');
  Lines.Add('Write-Host "[info] Script   : $($cand.Name)" -ForegroundColor Cyan');
  Lines.Add('Write-Host "[info] Threads  : $Threads" -ForegroundColor Cyan');
  if Args_ = '--serve-only' then
    Lines.Add('Write-Host "[info] Mode     : serve-only (press Ctrl+C to stop)" -ForegroundColor Cyan')
  else
    Lines.Add('Write-Host "[info] Mode     : call test (exits with status code)" -ForegroundColor Cyan');
  Lines.Add('Write-Host ""');
  Lines.Add('');
  Lines.Add('Push-Location $cleanDir');
  Lines.Add('try {');
  if Args_ = '--serve-only' then
    Lines.Add('    & $juliaCmd.Source "--project=." "--threads=$Threads" $cand.FullName "--serve-only"')
  else
    Lines.Add('    & $juliaCmd.Source "--project=." "--threads=$Threads" $cand.FullName');
  Lines.Add('    $rc = $LASTEXITCODE');
  Lines.Add('} finally {');
  Lines.Add('    Pop-Location');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('exit $rc');
  Lines.Add('');
end;

function GenerateABIRunServiceScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;

  Lines := TPascalStringList.Create;
  try
    EmitRunHeader(Lines);
    Lines.Add('if ($Help) {');
    Lines.Add('    Write-Host "Usage: run_julia_service.ps1 [-GenDir <path>] [-Threads <n>] [-Help]"');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Starts the Julia ABI service in serve-only mode (no client test in the same process)."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Prerequisites:"');
    Lines.Add('    Write-Host "  1. code_decl_to_abi has generated the .jl files."');
    Lines.Add('    Write-Host "  2. setup_julia_tests.ps1 has completed successfully."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Run this in Terminal A. Then run run_julia_call.ps1 in Terminal B."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Optional:"');
    Lines.Add('    Write-Host "  -GenDir <path>   Generated project directory. Default: this script directory."');
    Lines.Add('    Write-Host "  -Threads <n>     Julia thread count. Default: 2. Must be >= 2."');
    Lines.Add('    Write-Host "  -Help            Show this help."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Press Ctrl+C to stop the service."');
    Lines.Add('    exit 0');
    Lines.Add('}');
    Lines.Add('');
    EmitRunCommonResolve(Lines, TP_String('_abi_service_test'), TP_String('--serve-only'));
    Result := Lines;
    Log(PFormat('Generated run_julia_service.ps1: %d lines', [Lines.Count]));
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

function GenerateABIRunCallScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;

  Lines := TPascalStringList.Create;
  try
    EmitRunHeader(Lines);
    Lines.Add('if ($Help) {');
    Lines.Add('    Write-Host "Usage: run_julia_call.ps1 [-GenDir <path>] [-Threads <n>] [-Help]"');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Runs the Julia ABI call test against a running service."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Prerequisites:"');
    Lines.Add('    Write-Host "  1. code_decl_to_abi has generated the .jl files."');
    Lines.Add('    Write-Host "  2. setup_julia_tests.ps1 has completed successfully."');
    Lines.Add('    Write-Host "  3. run_julia_service.ps1 is currently running in Terminal A."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Optional:"');
    Lines.Add('    Write-Host "  -GenDir <path>   Generated project directory. Default: this script directory."');
    Lines.Add('    Write-Host "  -Threads <n>     Julia thread count. Default: 2. Must be >= 2."');
    Lines.Add('    Write-Host "  -Help            Show this help."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Exit code: 0 when all checks PASS or SKIP; 2 if any FAIL."');
    Lines.Add('    exit 0');
    Lines.Add('}');
    Lines.Add('');
    EmitRunCommonResolve(Lines, TP_String('_abi_call_test'), TP_String(''));
    Result := Lines;
    Log(PFormat('Generated run_julia_call.ps1: %d lines', [Lines.Count]));
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization

  RegisterGenerator(
    'julia',
    'Project.toml',
    gkProject,
    'Julia project metadata',
    @GenerateABIProjectToml);

  RegisterGenerator(
    'julia',
    'runtests.jl',
    gkTest,
    'Julia test entry point',
    @GenerateABIRunTests);

  RegisterGenerator(
    'julia',
    'setup_julia_tests.ps1',
    gkPs1,
    'Julia ABI test environment setup script (environment only, no test execution)',
    @GenerateABISetupScript);

  RegisterGenerator(
    'julia',
    'run_julia_service.ps1',
    gkPs1,
    'Run the Julia ABI service test in serve-only mode',
    @GenerateABIRunServiceScript);

  RegisterGenerator(
    'julia',
    'run_julia_call.ps1',
    gkPs1,
    'Run the Julia ABI call test',
    @GenerateABIRunCallScript);

end.
