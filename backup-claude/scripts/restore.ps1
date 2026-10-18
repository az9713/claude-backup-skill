# Restores a backup.ps1 zip onto this machine. Merges into what is there; overwritten items are copied aside first.
# Run from a plain PowerShell window, NOT from inside Claude Code. Close Claude Code and Claude Desktop first.
# Usage: powershell -ExecutionPolicy Bypass -File restore.ps1 -Zip D:\claude-backup-OLDPC-20261017-1200.zip
param([Parameter(Mandatory)][string]$Zip)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Get-Process claude -ErrorAction SilentlyContinue) {
  throw 'A Claude process is running. Close Claude Code and Claude Desktop, then run again.'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$stage = Join-Path $env:TEMP "claude-restore-$stamp"
$safety = Join-Path $env:USERPROFILE "claude-pre-restore-$stamp"
New-Item -ItemType Directory $stage | Out-Null
Write-Host "Extracting $Zip ..."
try { [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $stage) }
catch { throw "Extract failed: $($_.Exception.GetBaseException().Message). Nothing was restored. Staging: $stage" }

$m = Get-Content "$stage\claude-backup-manifest.json" -Raw | ConvertFrom-Json
if ($m.profile -ne $env:USERPROFILE) {
  Write-Warning ("Backup came from $($m.profile), this profile is $env:USERPROFILE. " +
    "Session folders in .claude\projects and paths in settings.json, .claude.json and claude_desktop_config.json " +
    "still name the old path. Edit them by hand.")
}

function Copy-Tree($from, $to) {
  if (Test-Path $from -PathType Container) {
    robocopy $from $to /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE): $from -> $to" }
  } else {
    New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
    Copy-Item $from $to -Force
  }
}

$map = [ordered]@{
  "$stage\.claude"      = "$env:USERPROFILE\.claude"
  "$stage\.claude.json" = "$env:USERPROFILE\.claude.json"
  "$stage\AGENTS.md"    = "$env:USERPROFILE\AGENTS.md"
}
Get-ChildItem "$stage\Claude" -Force -ErrorAction SilentlyContinue |
  ForEach-Object { $map[$_.FullName] = "$env:APPDATA\Claude\$($_.Name)" }

foreach ($src in $map.Keys) {
  if (-not (Test-Path $src)) { continue }
  $dst = $map[$src]
  if (Test-Path $dst) { Copy-Tree $dst ($dst.Replace($env:USERPROFILE, $safety)) }
  Copy-Tree $src $dst
  "restored $dst"
}
Remove-Item $stage -Recurse -Force
if (Test-Path $safety) { "Items that existed before the restore were copied to $safety. Delete it when all works." }
'Done. Start Claude Code. If it asks you to log in, run /login.'
