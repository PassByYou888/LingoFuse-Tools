unit java_abi_test_setup_generator_tool;

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

function GenerateJavaPomXml(Model: TPascal_Func_Model): TPascalStringList;
function GenerateJavaSetupScript(Model: TPascal_Func_Model): TPascalStringList;
function GenerateJavaRunServiceScript(Model: TPascal_Func_Model): TPascalStringList;
function GenerateJavaRunCallScript(Model: TPascal_Func_Model): TPascalStringList;

const
  GenerateCode_LogEnabled: boolean = False;

implementation

uses
  SysUtils;

procedure Log(const Msg: TP_String); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[java_abi_test_setup_generator] %s', [Msg.Text]);
end;

procedure Log(const Fmt: TP_String; const Args: array of const); overload;
begin
  if GenerateCode_LogEnabled then
    DoStatus('[java_abi_test_setup_generator] %s', [PFormat(Fmt, Args)]);
end;

function LowerUnitName(const UnitName: TP_String): TP_String;
var
  i: integer;
  c: TP_Char;
begin
  Result := TP_String('');
  for i := 1 to UnitName.Len do
  begin
    c := UnitName[i];
    if (c >= 'A') and (c <= 'Z') then
      Result.Append(TP_Char(Ord(c) + 32))
    else if (c = '_') or ((c >= 'a') and (c <= 'z')) or
            ((c >= '0') and (c <= '9')) then
      Result.Append(c)
    else
      Result.Append(TP_Char('_'));
  end;
end;

function JavaArtifactId(const UnitName: TP_String): TP_String;
begin
  Result := LowerUnitName(UnitName) + TP_String('_abi');
end;

function GenerateJavaPomXml(Model: TPascal_Func_Model): TPascalStringList;
var
  UnitName, ArtifactId: TP_String;
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then
  begin
    Log(TP_String('GenerateJavaPomXml: Model is nil'));
    Exit;
  end;
  UnitName := Model.UnitName;
  if UnitName.Len = 0 then
  begin
    Log(TP_String('GenerateJavaPomXml: UnitName is empty'));
    Exit;
  end;
  ArtifactId := JavaArtifactId(UnitName);
  Log(TP_String(PFormat('Generating pom.xml for unit "%s"', [UnitName.Text])));

  Lines := TPascalStringList.Create;
  try
    Lines.Add('<?xml version="1.0" encoding="UTF-8"?>');
    Lines.Add('<project xmlns="http://maven.apache.org/POM/4.0.0"');
    Lines.Add('         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"');
    Lines.Add('         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">');
    Lines.Add('    <modelVersion>4.0.0</modelVersion>');
    Lines.Add('    <groupId>lingofuse.abi</groupId>');
    Lines.Add('    <artifactId>' + ArtifactId.Text + '</artifactId>');
    Lines.Add('    <version>1.0.0</version>');
    Lines.Add('    <packaging>jar</packaging>');
    Lines.Add('');
    Lines.Add('    <properties>');
    Lines.Add('        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>');
    Lines.Add('        <maven.compiler.release>22</maven.compiler.release>');
    Lines.Add('        <lingofuse.java.jar>${project.basedir}/lib/lingofuse.jar</lingofuse.java.jar>');
    Lines.Add('    </properties>');
    Lines.Add('');
    Lines.Add('    <dependencies>');
    Lines.Add('        <dependency>');
    Lines.Add('            <groupId>lingofuse</groupId>');
    Lines.Add('            <artifactId>lingofuse</artifactId>');
    Lines.Add('            <version>1.0.0</version>');
    Lines.Add('            <scope>system</scope>');
    Lines.Add('            <systemPath>${lingofuse.java.jar}</systemPath>');
    Lines.Add('        </dependency>');
    Lines.Add('        <dependency>');
    Lines.Add('            <groupId>com.fasterxml.jackson.core</groupId>');
    Lines.Add('            <artifactId>jackson-databind</artifactId>');
    Lines.Add('            <version>2.17.0</version>');
    Lines.Add('        </dependency>');
    Lines.Add('    </dependencies>');
    Lines.Add('');
    Lines.Add('    <build>');
    Lines.Add('        <plugins>');
    Lines.Add('            <plugin>');
    Lines.Add('                <groupId>org.codehaus.mojo</groupId>');
    Lines.Add('                <artifactId>exec-maven-plugin</artifactId>');
    Lines.Add('                <version>3.1.0</version>');
    Lines.Add('                <configuration>');
    Lines.Add('                    <classpathScope>compile</classpathScope>');
    Lines.Add('                </configuration>');
    Lines.Add('            </plugin>');
    Lines.Add('        </plugins>');
    Lines.Add('    </build>');
    Lines.Add('</project>');
    Lines.Add('');

    Result := Lines;
    Log(TP_String(PFormat('Generated pom.xml: %d lines', [Lines.Count])));
  finally
  end;
end;

procedure EmitSetupHeader(Lines: TPascalStringList);
begin
  Lines.Add('#Requires -Version 5.1');
  Lines.Add('');
  Lines.Add('[CmdletBinding()]');
  Lines.Add('param(');
  Lines.Add('    [string]$LingoFuseJava = "",');
  Lines.Add('    [string]$LingoFuseJar  = "",');
  Lines.Add('    [string]$LingoFuseLib  = "",');
  Lines.Add('    [string]$GenDir        = "",');
  Lines.Add('    [string]$UnitName      = "",');
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
end;

procedure EmitSetupHelp(Lines: TPascalStringList);
begin
  Lines.Add('if ($Help) {');
  Lines.Add('    Write-Host "Usage: setup_java_tests.ps1 -LingoFuseJava <path> [options]"');
  Lines.Add('    Write-Host "       setup_java_tests.ps1 -LingoFuseJar  <jar>  [options]"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "One-shot Java test environment bootstrap for LingoFuse ABI generated code."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "How it works:"');
  Lines.Add('    Write-Host "  1. Validate the LingoFuse java project or the lingofuse.jar file."');
  Lines.Add('    Write-Host "  2. If the java project has no built jar yet, run: mvn -Dmaven.test.skip=true package"');
  Lines.Add('    Write-Host "  3. Create a clean build directory (<GenDir>/.java_clean_build/) with:"');
  Lines.Add('    Write-Host "         pom.xml                                 (from the generated project)"');
  Lines.Add('    Write-Host "         lib/lingofuse.jar                       (copied from the java project)"');
  Lines.Add('    Write-Host "         src/main/java/lingofuse/abi/<lower>/    (the 4 generated .java files)"');
  Lines.Add('    Write-Host "         LingoFuse64.dll / liblingofuse.so / ... (auto-detected dynamic library)"');
  Lines.Add('    Write-Host "  4. Verify with: mvn -q -DskipTests compile"');
  Lines.Add('    Write-Host "  5. Print the next-step commands."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Required (one of):"');
  Lines.Add('    Write-Host "  -LingoFuseJava <path>"');
  Lines.Add('    Write-Host "        Path to the LingoFuse java project (contains pom.xml and target/lingofuse*.jar)."');
  Lines.Add('    Write-Host "        If target/lingofuse*.jar is missing, this script will run mvn package for you."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "  -LingoFuseJar <jar>"');
  Lines.Add('    Write-Host "        Path to a pre-built lingofuse.jar file."');
  Lines.Add('    Write-Host "        Use this if you already have the jar in a known location."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Optional:"');
  Lines.Add('    Write-Host "  -LingoFuseLib <path>"');
  Lines.Add('    Write-Host "        Path to the LingoFuse dynamic library (LingoFuse64.dll, liblingofuse.so, etc.)."');
  Lines.Add('    Write-Host "        Can be a directory or a file. If omitted, the script searches:"');
  Lines.Add('    Write-Host "            <GenDir>"');
  Lines.Add('    Write-Host "            <LingoFuseJava>/.."');
  Lines.Add('    Write-Host "  -GenDir <path>         Generated project directory. Default: this script directory."');
  Lines.Add('    Write-Host "  -UnitName <name>       Source unit name. Default: auto-detect from *AbiServiceMain.java."');
  Lines.Add('    Write-Host "  -Force                 Recreate the clean build directory from scratch."');
  Lines.Add('    Write-Host "  -Clean                 Delete the clean build directory after setup succeeds."');
  Lines.Add('    Write-Host "  -Help                  Show this help."');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Examples:"');
  Lines.Add('    Write-Host "  .\setup_java_tests.ps1 -LingoFuseJava D:\CoreLibrary\LingoFuse\java"');
  Lines.Add('    Write-Host "  .\setup_java_tests.ps1 -LingoFuseJava D:\CoreLibrary\LingoFuse\java -Force"');
  Lines.Add('    Write-Host "  .\setup_java_tests.ps1 -LingoFuseJar D:\libs\lingofuse.jar -LingoFuseLib D:\libs\LingoFuse64.dll"');
  Lines.Add('    Write-Host ""');
  Lines.Add('    Write-Host "Exit codes:"');
  Lines.Add('    Write-Host "  0   success"');
  Lines.Add('    Write-Host "  1   validation failed, missing tool, or build failed"');
  Lines.Add('    exit 0');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupValidateArgs(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $LingoFuseJava -and -not $LingoFuseJar) {');
  Lines.Add('    Write-Fail "Either -LingoFuseJava or -LingoFuseJar must be provided."');
  Lines.Add('    Write-Fail "        Run setup_java_tests.ps1 -Help for usage."');
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
  Lines.Add('Write-Info "GenDir      : $GenDir"');
  Lines.Add('');
end;

procedure EmitSetupToolCheck(Lines: TPascalStringList);
begin
  Lines.Add('$javaCmd = Get-Command java -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $javaCmd) {');
  Lines.Add('    Write-Fail "java is not on PATH."');
  Lines.Add('    Write-Fail "        Install JDK 22 or later: https://jdk.java.net/22/"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$javaVerOut = ((& java -version 2>&1) | Out-String)');
  Lines.Add('if ($javaVerOut -match ' + #39 + 'version\s+"?([\d._]+)"?' + #39 + ') {');
  Lines.Add('    Write-Ok "java: $($matches[1])"');
  Lines.Add('} else {');
  Lines.Add('    Write-Ok "java: present"');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$mvnCmd = Get-Command mvn -ErrorAction SilentlyContinue');
  Lines.Add('if ($null -eq $mvnCmd) {');
  Lines.Add('    Write-Fail "mvn is not on PATH."');
  Lines.Add('    Write-Fail "        Install Maven 3.9 or later: https://maven.apache.org/download.cgi"');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$mvnVerOut = ((& mvn "-v" 2>&1) | Out-String)');
  Lines.Add('if ($mvnVerOut -match ' + #39 + 'Apache Maven\s+([\d.]+)' + #39 + ') {');
  Lines.Add('    Write-Ok "mvn : $($matches[1])"');
  Lines.Add('} else {');
  Lines.Add('    Write-Ok "mvn : present"');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupDetectUnitName(Lines: TPascalStringList);
begin
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    $cand = Get-ChildItem -LiteralPath $GenDir -File -Filter "*AbiServiceMain.java" -ErrorAction SilentlyContinue | Select-Object -First 1');
  Lines.Add('    if ($null -ne $cand) {');
  Lines.Add('        $UnitName = $cand.Name -replace ' + #39 + 'AbiServiceMain\.java$' + #39 + ', ' + #39 + #39);
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('if (-not $UnitName) {');
  Lines.Add('    Write-Fail "Cannot auto-detect UnitName (no *AbiServiceMain.java in $GenDir)."');
  Lines.Add('    Write-Fail "        Pass -UnitName explicitly."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Info "UnitName: $UnitName"');
  Lines.Add('');
  Lines.Add('$lowerUnit = $UnitName.ToLower()');
  Lines.Add('$pkg = "lingofuse.abi.$lowerUnit"');
  Lines.Add('$pkgPath = $pkg.Replace(' + #39 + '.' + #39 + ', ' + #39 + '/' + #39 + ')');
  Lines.Add('');
end;

procedure EmitSetupCheckGeneratedFiles(Lines: TPascalStringList);
begin
  Lines.Add('$serviceJava     = Join-Path $GenDir "${UnitName}AbiService.java"');
  Lines.Add('$callJava        = Join-Path $GenDir "${UnitName}AbiCall.java"');
  Lines.Add('$serviceMainJava = Join-Path $GenDir "${UnitName}AbiServiceMain.java"');
  Lines.Add('$callMainJava    = Join-Path $GenDir "${UnitName}AbiCallTestMain.java"');
  Lines.Add('$pomSrc          = Join-Path $GenDir "pom.xml"');
  Lines.Add('');
  Lines.Add('$missing = @()');
  Lines.Add('foreach ($p in @($serviceJava, $callJava, $serviceMainJava, $callMainJava, $pomSrc)) {');
  Lines.Add('    if (-not (Test-Path -LiteralPath $p)) { $missing += $p }');
  Lines.Add('}');
  Lines.Add('if ($missing.Count -gt 0) {');
  Lines.Add('    Write-Fail "Missing generated Java files:"');
  Lines.Add('    foreach ($m in $missing) { Write-Host "        $m" }');
  Lines.Add('    Write-Fail "Run code_decl_to_abi first to emit the .java files and pom.xml."');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('Write-Ok "All generated Java files present."');
  Lines.Add('');
end;

procedure EmitSetupDetectJar(Lines: TPascalStringList);
begin
  Lines.Add('if ($LingoFuseJar) {');
  Lines.Add('    if (-not (Test-Path -LiteralPath $LingoFuseJar)) {');
  Lines.Add('        Write-Fail "LingoFuseJar not found: $LingoFuseJar"');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    $LingoFuseJar = (Resolve-Path -LiteralPath $LingoFuseJar).Path');
  Lines.Add('} else {');
  Lines.Add('    if (-not (Test-Path -LiteralPath $LingoFuseJava)) {');
  Lines.Add('        Write-Fail "LingoFuseJava not found: $LingoFuseJava"');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    $LingoFuseJava = (Resolve-Path -LiteralPath $LingoFuseJava).Path');
  Lines.Add('    $lfPom = Join-Path $LingoFuseJava "pom.xml"');
  Lines.Add('    if (-not (Test-Path -LiteralPath $lfPom)) {');
  Lines.Add('        Write-Fail "Missing pom.xml in LingoFuseJava: $lfPom"');
  Lines.Add('        Write-Fail "        -LingoFuseJava must point at the LingoFuse java project directory."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    function Find-LingofuseJar {');
  Lines.Add('        param([string]$BaseDir)');
  Lines.Add('        $lfTarget = Join-Path $BaseDir "target"');
  Lines.Add('        if (-not (Test-Path -LiteralPath $lfTarget)) { return $null }');
  Lines.Add('        $cands = @(Get-ChildItem -LiteralPath $lfTarget -Filter "lingofuse*.jar" -File -ErrorAction SilentlyContinue |');
  Lines.Add('            Where-Object {');
  Lines.Add('                $_.Name -notlike "*-sources.jar" -and');
  Lines.Add('                $_.Name -notlike "*-javadoc.jar" -and');
  Lines.Add('                $_.Name -notlike "*-tests.jar"');
  Lines.Add('            })');
  Lines.Add('        if ($cands.Count -eq 0) { return $null }');
  Lines.Add('        return $cands[0].FullName');
  Lines.Add('    }');
  Lines.Add('');
  Lines.Add('    $LingoFuseJar = Find-LingofuseJar $LingoFuseJava');
  Lines.Add('    if (-not $LingoFuseJar) {');
  Lines.Add('        Write-Warn "No lingofuse*.jar found in $LingoFuseJava\target."');
  Lines.Add('        Write-Warn "        Running: mvn -Dmaven.test.skip=true package ..."');
  Lines.Add('        Push-Location $LingoFuseJava');
  Lines.Add('        try {');
  Lines.Add('            & mvn "-Dmaven.test.skip=true" package');
  Lines.Add('            $rc = $LASTEXITCODE');
  Lines.Add('            if ($rc -ne 0) {');
  Lines.Add('                Write-Fail "mvn package failed (exit $rc)."');
  Lines.Add('                Write-Fail "        See the errors above for details."');
  Lines.Add('                exit 1');
  Lines.Add('            }');
  Lines.Add('        } finally {');
  Lines.Add('            Pop-Location');
  Lines.Add('        }');
  Lines.Add('        $LingoFuseJar = Find-LingofuseJar $LingoFuseJava');
  Lines.Add('        if (-not $LingoFuseJar) {');
  Lines.Add('            Write-Fail "mvn package succeeded but no lingofuse*.jar was produced."');
  Lines.Add('            Write-Fail "        Check that the LingoFuse java project has <packaging>jar</packaging>."');
  Lines.Add('            exit 1');
  Lines.Add('        }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('Write-Ok "LingoFuse jar: $LingoFuseJar"');
  Lines.Add('');
end;

procedure EmitSetupDetectLib(Lines: TPascalStringList);
begin
  Lines.Add('$libExtensions = @(".dll", ".so", ".dylib")');
  Lines.Add('$libFound = $null');
  Lines.Add('');
  Lines.Add('if ($LingoFuseLib) {');
  Lines.Add('    if (Test-Path -LiteralPath $LingoFuseLib -PathType Container) {');
  Lines.Add('        foreach ($ext in $libExtensions) {');
  Lines.Add('            $cands = @(Get-ChildItem -LiteralPath $LingoFuseLib -File -Filter "*$ext" -ErrorAction SilentlyContinue)');
  Lines.Add('            if ($cands.Count -gt 0) { $libFound = $cands[0].FullName; break }');
  Lines.Add('        }');
  Lines.Add('    } elseif (Test-Path -LiteralPath $LingoFuseLib -PathType Leaf) {');
  Lines.Add('        $libFound = (Resolve-Path -LiteralPath $LingoFuseLib).Path');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $libFound) {');
  Lines.Add('    $libSearchDirs = @($GenDir)');
  Lines.Add('    if ($LingoFuseJava) {');
  Lines.Add('        $libSearchDirs += (Split-Path $LingoFuseJava -Parent)');
  Lines.Add('    }');
  Lines.Add('    foreach ($d in $libSearchDirs) {');
  Lines.Add('        if (-not (Test-Path -LiteralPath $d)) { continue }');
  Lines.Add('        foreach ($ext in $libExtensions) {');
  Lines.Add('            $cands = @(Get-ChildItem -LiteralPath $d -File -Filter "*$ext" -ErrorAction SilentlyContinue)');
  Lines.Add('            if ($cands.Count -gt 0) { $libFound = $cands[0].FullName; break }');
  Lines.Add('        }');
  Lines.Add('        if ($libFound) { break }');
  Lines.Add('    }');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('if (-not $libFound) {');
  Lines.Add('    Write-Warn "No dynamic library found (.dll / .so / .dylib)."');
  Lines.Add('    Write-Warn "        The test programs will fail to load LingoFuse at runtime."');
  Lines.Add('    Write-Warn "        Use -LingoFuseLib <path> to specify one explicitly, or place the library in $GenDir."');
  Lines.Add('    $copyLib = $false');
  Lines.Add('} else {');
  Lines.Add('    Write-Ok "Dynamic library: $libFound"');
  Lines.Add('    $copyLib = $true');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupCreateCleanDir(Lines: TPascalStringList);
begin
  Lines.Add('$cleanDir = Join-Path $GenDir ".java_clean_build"');
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
  Lines.Add('$libDir = Join-Path $cleanDir "lib"');
  Lines.Add('$srcDir = Join-Path $cleanDir "src/main/java/$pkgPath"');
  Lines.Add('New-Item -ItemType Directory -Path $libDir -Force | Out-Null');
  Lines.Add('New-Item -ItemType Directory -Path $srcDir -Force | Out-Null');
  Lines.Add('');
end;

procedure EmitSetupCopyFiles(Lines: TPascalStringList);
begin
  Lines.Add('Copy-Item -LiteralPath $pomSrc -Destination (Join-Path $cleanDir "pom.xml") -Force');
  Lines.Add('Write-Ok "Copied pom.xml -> $cleanDir/pom.xml"');
  Lines.Add('');
  Lines.Add('Copy-Item -LiteralPath $LingoFuseJar -Destination (Join-Path $libDir "lingofuse.jar") -Force');
  Lines.Add('Write-Ok "Copied lingofuse.jar -> lib/lingofuse.jar"');
  Lines.Add('');
  Lines.Add('foreach ($src in @($serviceJava, $callJava, $serviceMainJava, $callMainJava)) {');
  Lines.Add('    Copy-Item -LiteralPath $src -Destination (Join-Path $srcDir (Split-Path $src -Leaf)) -Force');
  Lines.Add('}');
  Lines.Add('Write-Ok "Copied 4 .java files into src/main/java/$pkgPath/"');
  Lines.Add('');
  Lines.Add('if ($copyLib) {');
  Lines.Add('    Copy-Item -LiteralPath $libFound -Destination (Join-Path $cleanDir (Split-Path $libFound -Leaf)) -Force');
  Lines.Add('    Write-Ok "Copied dynamic library: $(Split-Path $libFound -Leaf)"');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupCompile(Lines: TPascalStringList);
begin
  Lines.Add('Push-Location $cleanDir');
  Lines.Add('try {');
  Lines.Add('    Write-Info "Running mvn -q -DskipTests compile ..."');
  Lines.Add('    & mvn "-q" "-DskipTests" compile');
  Lines.Add('    $rc = $LASTEXITCODE');
  Lines.Add('    if ($rc -ne 0) {');
  Lines.Add('        Write-Fail "mvn compile failed (exit $rc)."');
  Lines.Add('        Write-Fail "        See the errors above for details."');
  Lines.Add('        exit 1');
  Lines.Add('    }');
  Lines.Add('    Write-Ok "mvn compile passed."');
  Lines.Add('} finally {');
  Lines.Add('    Pop-Location');
  Lines.Add('}');
  Lines.Add('');
end;

procedure EmitSetupNextSteps(Lines: TPascalStringList);
begin
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Environment is ready." -ForegroundColor Green');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Clean directory: $cleanDir" -ForegroundColor Cyan');
  Lines.Add('Write-Host "Main classes:" -ForegroundColor Cyan');
  Lines.Add('Write-Host "    $pkg.${UnitName}AbiServiceMain"');
  Lines.Add('Write-Host "    $pkg.${UnitName}AbiCallTestMain"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "Run in two separate terminals:" -ForegroundColor Cyan');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  Terminal 1 (service):" -ForegroundColor Yellow');
  Lines.Add('Write-Host "      cd `"$GenDir`""');
  Lines.Add('Write-Host "      .\run_java_service.ps1"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "  Terminal 2 (call):" -ForegroundColor Yellow');
  Lines.Add('Write-Host "      cd `"$GenDir`""');
  Lines.Add('Write-Host "      .\run_java_call.ps1"');
  Lines.Add('Write-Host ""');
  Lines.Add('Write-Host "The service waits for Enter; press Enter to stop it." -ForegroundColor DarkGray');
  Lines.Add('Write-Host "The call test exits with code 0 when all tests pass, 2 otherwise." -ForegroundColor DarkGray');
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

function GenerateJavaSetupScript(Model: TPascal_Func_Model): TPascalStringList;
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
    EmitSetupDetectJar(Lines);
    EmitSetupDetectLib(Lines);
    EmitSetupCreateCleanDir(Lines);
    EmitSetupCopyFiles(Lines);
    EmitSetupCompile(Lines);
    EmitSetupNextSteps(Lines);
    Result := Lines;
    Log(TP_String(PFormat('Generated setup_java_tests.ps1: %d lines',
      [Lines.Count])));
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
  Lines.Add('    [switch]$Help');
  Lines.Add(')');
  Lines.Add('');
  Lines.Add('$ErrorActionPreference = "Stop"');
  Lines.Add('');
end;

procedure EmitRunCommonResolve(Lines: TPascalStringList;
  const MainSuffix: TP_String);
begin
  Lines.Add('if (-not $GenDir) { $GenDir = $PSScriptRoot }');
  Lines.Add('if (-not (Test-Path -LiteralPath $GenDir)) {');
  Lines.Add('    Write-Host "[fail] GenDir not found: $GenDir" -ForegroundColor Red');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$GenDir = (Resolve-Path -LiteralPath $GenDir).Path');
  Lines.Add('');
  Lines.Add('$cleanDir = Join-Path $GenDir ".java_clean_build"');
  Lines.Add('if (-not (Test-Path -LiteralPath $cleanDir)) {');
  Lines.Add('    Write-Host "[fail] Clean directory not found: $cleanDir" -ForegroundColor Red');
  Lines.Add('    Write-Host "[fail] Run setup_java_tests.ps1 first." -ForegroundColor Red');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$srcRoot = Join-Path $cleanDir "src/main/java"');
  Lines.Add('if (-not (Test-Path -LiteralPath $srcRoot)) {');
  Lines.Add('    Write-Host "[fail] Source root not found: $srcRoot" -ForegroundColor Red');
  Lines.Add('    Write-Host "[fail] The clean directory is corrupted. Re-run setup_java_tests.ps1 -Force." -ForegroundColor Red');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('$cand = Get-ChildItem -LiteralPath $srcRoot -Filter "*' + MainSuffix.Text + '.java" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1');
  Lines.Add('if ($null -eq $cand) {');
  Lines.Add('    Write-Host "[fail] Cannot find *' + MainSuffix.Text + '.java under $srcRoot" -ForegroundColor Red');
  Lines.Add('    exit 1');
  Lines.Add('}');
  Lines.Add('$UnitName = $cand.Name -replace ' + #39 + MainSuffix.Text + '\.java$' + #39 + ', ' + #39 + #39);
  Lines.Add('$lowerUnit = $UnitName.ToLower()');
  Lines.Add('$mainClass = "lingofuse.abi.$lowerUnit.${UnitName}' + MainSuffix.Text + '"');
  Lines.Add('');
  Lines.Add('Write-Host "[info] UnitName : $UnitName" -ForegroundColor Cyan');
  Lines.Add('Write-Host "[info] MainClass: $mainClass" -ForegroundColor Cyan');
  Lines.Add('Write-Host "[info] CleanDir : $cleanDir" -ForegroundColor Cyan');
  Lines.Add('Write-Host ""');
  Lines.Add('');
  Lines.Add('Push-Location $cleanDir');
  Lines.Add('try {');
  Lines.Add('    & mvn "-q" "-DskipTests" compile "exec:java" "-Dexec.mainClass=$mainClass"');
  Lines.Add('    $rc = $LASTEXITCODE');
  Lines.Add('    if ($rc -ne 0) {');
  Lines.Add('        Write-Host "[fail] mvn exit code: $rc" -ForegroundColor Red');
  Lines.Add('        exit $rc');
  Lines.Add('    }');
  Lines.Add('} finally {');
  Lines.Add('    Pop-Location');
  Lines.Add('}');
  Lines.Add('');
  Lines.Add('exit 0');
  Lines.Add('');
end;

function GenerateJavaRunServiceScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;

  Lines := TPascalStringList.Create;
  try
    EmitRunHeader(Lines);
    Lines.Add('if ($Help) {');
    Lines.Add('    Write-Host "Usage: run_java_service.ps1 [-GenDir <path>] [-Help]"');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Runs the Java ABI service test program from the clean build directory."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Prerequisites:"');
    Lines.Add('    Write-Host "  1. code_decl_to_abi has generated the Java files."');
    Lines.Add('    Write-Host "  2. setup_java_tests.ps1 has completed successfully."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Optional:"');
    Lines.Add('    Write-Host "  -GenDir <path>   Generated project directory. Default: this script directory."');
    Lines.Add('    Write-Host "  -Help            Show this help."');
    Lines.Add('    exit 0');
    Lines.Add('}');
    Lines.Add('');
    EmitRunCommonResolve(Lines, TP_String('AbiServiceMain'));
    Result := Lines;
    Log(TP_String(PFormat('Generated run_java_service.ps1: %d lines',
      [Lines.Count])));
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

function GenerateJavaRunCallScript(Model: TPascal_Func_Model): TPascalStringList;
var
  Lines: TPascalStringList;
begin
  Result := nil;
  if Model = nil then Exit;

  Lines := TPascalStringList.Create;
  try
    EmitRunHeader(Lines);
    Lines.Add('if ($Help) {');
    Lines.Add('    Write-Host "Usage: run_java_call.ps1 [-GenDir <path>] [-Help]"');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Runs the Java ABI call test program from the clean build directory."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Prerequisites:"');
    Lines.Add('    Write-Host "  1. code_decl_to_abi has generated the Java files."');
    Lines.Add('    Write-Host "  2. setup_java_tests.ps1 has completed successfully."');
    Lines.Add('    Write-Host "  3. run_java_service.ps1 is currently running in another terminal."');
    Lines.Add('    Write-Host ""');
    Lines.Add('    Write-Host "Optional:"');
    Lines.Add('    Write-Host "  -GenDir <path>   Generated project directory. Default: this script directory."');
    Lines.Add('    Write-Host "  -Help            Show this help."');
    Lines.Add('    exit 0');
    Lines.Add('}');
    Lines.Add('');
    EmitRunCommonResolve(Lines, TP_String('AbiCallTestMain'));
    Result := Lines;
    Log(TP_String(PFormat('Generated run_java_call.ps1: %d lines',
      [Lines.Count])));
  finally
    if Result <> Lines then
      Lines.Free;
  end;
end;

initialization

  RegisterGenerator(
    'java',
    'pom.xml',
    gkProject,
    'Maven build file for the generated Java ABI project',
    @GenerateJavaPomXml);

  RegisterGenerator(
    'java',
    'setup_java_tests.ps1',
    gkPs1,
    'Java ABI test environment setup script',
    @GenerateJavaSetupScript);

  RegisterGenerator(
    'java',
    'run_java_service.ps1',
    gkPs1,
    'Run the Java ABI service test program',
    @GenerateJavaRunServiceScript);

  RegisterGenerator(
    'java',
    'run_java_call.ps1',
    gkPs1,
    'Run the Java ABI call test program',
    @GenerateJavaRunCallScript);

end.
