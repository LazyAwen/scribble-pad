# Creates the Windows plugin symlink directory as *junctions* instead of
# symlinks. Flutter requires symlink privileges (Developer Mode / admin) to
# create the real thing; junctions (mklink /J) need none, and the flutter tool
# skips any link that already exists, so pre-creating them is enough.
param([string]$Project = "D:\Work\scribble-pad")

$ErrorActionPreference = "Stop"
$deps = Join-Path $Project ".flutter-plugins-dependencies"
if (-not (Test-Path $deps)) {
  Write-Host "no .flutter-plugins-dependencies - run 'flutter pub get' first"
  exit 1
}

$base = Join-Path $Project "windows\flutter\ephemeral\.plugin_symlinks"
New-Item -ItemType Directory -Force -Path $base | Out-Null

$json = Get-Content $deps -Raw | ConvertFrom-Json
foreach ($p in $json.plugins.windows) {
  $dest = Join-Path $base $p.name
  $src  = ($p.path -replace '\\\\', '\').TrimEnd('\')
  if (Test-Path $dest) {
    Write-Host "exists: $($p.name)"
    continue
  }
  if (-not (Test-Path $src)) {
    Write-Host "MISSING SOURCE: $src"
    continue
  }
  cmd /c mklink /J "$dest" "$src" | Out-Null
  Write-Host "junction: $($p.name) -> $src"
}
