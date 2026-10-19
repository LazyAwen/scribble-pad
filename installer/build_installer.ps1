# =============================================================================
#  涂想 Doodle — build the Windows installer (Inno Setup 6)
#  FULLY OFFLINE: no downloads, no network calls.
#
#  Usage (from anywhere):   powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
#  Requires:                flutter build windows --release  to have been run first
# =============================================================================

$ErrorActionPreference = 'Stop'

# --- ONE-LINE KNOB: the exe name produced by `flutter build windows` ---------
#     (CMake BINARY_NAME). >>> CHANGE THIS LINE ONLY if you rename the binary <<<
$AppExeName = 'doodle.exe'

# --- prepend Flutter to PATH (harmless if the folder does not exist here) ----
$env:PATH = "D:\dev\flutter\bin;" + $env:PATH

# --- locate the repo root (parent of the folder holding this script) ---------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
Set-Location $RepoRoot
Write-Host "Repo root : $RepoRoot"

# --- version from pubspec.yaml  (version: 2.0.0+2  ->  2.0.0) ---------------
$Pubspec = Join-Path $RepoRoot 'pubspec.yaml'
if (-not (Test-Path $Pubspec)) {
    Write-Host ""
    Write-Host "ERROR: pubspec.yaml not found at: $Pubspec" -ForegroundColor Red
    exit 1
}
$VersionLine = Get-Content $Pubspec | Select-String -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $VersionLine) {
    Write-Host ""
    Write-Host "ERROR: no ^version: line found in $Pubspec" -ForegroundColor Red
    exit 1
}
$RawVersion = $VersionLine.Matches[0].Groups[1].Value.Trim().Trim('"').Trim("'")
$AppVersion = ($RawVersion -split '\+')[0]
Write-Host "Version   : $AppVersion   (raw pubspec: $RawVersion)"

# --- check the Release build output ------------------------------------------
$ReleaseDir = Join-Path $RepoRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path $ReleaseDir)) {
    Write-Host ""
    Write-Host "ERROR: Release build output not found:" -ForegroundColor Red
    Write-Host "       $ReleaseDir" -ForegroundColor Red
    Write-Host ""
    Write-Host "Run this first, then re-run this script:" -ForegroundColor Yellow
    Write-Host "       flutter build windows --release" -ForegroundColor Yellow
    exit 1
}

$ExePath = Join-Path $ReleaseDir $AppExeName
if (-not (Test-Path $ExePath)) {
    # fall back to the previous binary name so a stale build still works
    $Legacy = Join-Path $ReleaseDir 'scribble_pad.exe'
    if (Test-Path $Legacy) {
        Write-Host "NOTE   : '$AppExeName' not found; falling back to 'scribble_pad.exe'." -ForegroundColor Yellow
        Write-Host "         Set BINARY_NAME in windows\CMakeLists.txt and rebuild to fix." -ForegroundColor Yellow
    }
    else {
        Write-Host ""
        Write-Host "ERROR: no '$AppExeName' (or scribble_pad.exe) in:" -ForegroundColor Red
        Write-Host "       $ReleaseDir" -ForegroundColor Red
        Write-Host ""
        Write-Host "Run this first, then re-run this script:" -ForegroundColor Yellow
        Write-Host "       flutter build windows --release" -ForegroundColor Yellow
        exit 1
    }
}
Write-Host "Build dir : $ReleaseDir"

# --- find ISCC.exe ------------------------------------------------------------
$Iscc = $null
$Candidates = @(
    'C:\Users\Awen\AppData\Local\Programs\Inno Setup 6\ISCC.exe'
)
foreach ($p in (Get-ChildItem 'C:\Program Files*\Inno Setup*\ISCC.exe' -ErrorAction SilentlyContinue)) {
    $Candidates += $p.FullName
}
foreach ($p in (Get-ChildItem 'C:\Program Files (x86)\Inno Setup*\ISCC.exe' -ErrorAction SilentlyContinue)) {
    $Candidates += $p.FullName
}
foreach ($c in $Candidates) { if (Test-Path $c) { $Iscc = $c; break } }

if (-not $Iscc) {
    Write-Host ""
    Write-Host "Inno Setup 6 not found. Installing it now..." -ForegroundColor Yellow
    winget install --id JRSoftware.InnoSetup --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
    foreach ($c in $Candidates) { if (Test-Path $c) { $Iscc = $c; break } }
}
if (-not $Iscc) {
    Write-Host ""
    Write-Host "ERROR: ISCC.exe not found. Install Inno Setup 6:" -ForegroundColor Red
    Write-Host "       winget install --id JRSoftware.InnoSetup --exact --accept-source-agreements --accept-package-agreements" -ForegroundColor Red
    exit 1
}
Write-Host "ISCC      : $Iscc"

# --- compile ------------------------------------------------------------------
Write-Host ""
Write-Host "Compiling installer\setup.iss ..." -ForegroundColor Cyan
& $Iscc "/DAppVer=$AppVersion" "installer\setup.iss"
$Code = $LASTEXITCODE

$OutFile = Join-Path $RepoRoot "installer\output\DoodleSetup-$AppVersion.exe"

if ($Code -ne 0) {
    Write-Host ""
    Write-Host "ERROR: ISCC failed with exit code $Code" -ForegroundColor Red
    exit $Code
}

Write-Host ""
if (Test-Path $OutFile) {
    $SizeMB = [math]::Round((Get-Item $OutFile).Length / 1MB, 1)
    Write-Host "SUCCESS - installer created:" -ForegroundColor Green
    Write-Host "  $OutFile  ($SizeMB MB)" -ForegroundColor Green
}
else {
    Write-Host "Compile finished, but expected output not found:" -ForegroundColor Yellow
    Write-Host "  $OutFile" -ForegroundColor Yellow
    Get-ChildItem (Join-Path $RepoRoot 'installer\output') -Filter '*.exe' -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  found: $($_.FullName)" }
}
