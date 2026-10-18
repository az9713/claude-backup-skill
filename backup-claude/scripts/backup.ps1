# Backs up Claude Code + Claude Desktop setup, skills, and sessions into one zip, with two receipts beside it:
#   <name>.files.txt   every file in the zip
#   <name>.skipped.txt every file or folder left out by an error, with the reason
# Usage: powershell -ExecutionPolicy Bypass -File backup.ps1 [-Dest D:\backups\claude]
param([string]$Dest = 'D:\backups\claude')   # D: = external drive; Windows can give it another letter
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
# ponytail: .NET ZipArchive, not tar.exe. bsdtar 3.8.9 crashed on non-ASCII file names, and after one unreadable
# entry it silently dropped the rest of that folder (2026-10-17: 613 Cowork session files lost).
New-Item -ItemType Directory -Force $Dest | Out-Null
$name = "claude-backup-$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd-HHmm')"
$zip = Join-Path $Dest "$name.zip"

# Rebuilt by Claude Code, or bound to this machine. Left out.
$excludes = '.claude/cache', '.claude/debug', '.claude/shell-snapshots', '.claude/paste-cache',
  '.claude/telemetry', '.claude/session-env', '.claude/statsig', '.claude/daemon.lock'
$homeItems = '.claude', '.claude.json', 'AGENTS.md' |
  Where-Object { Test-Path (Join-Path $env:USERPROFILE $_) }

# Claude Desktop: config + sessions only. The rest is browser cache, VM images (~10 GB, re-downloaded),
# or login state encrypted to this machine (config.json, Local Storage, Network).
$deskItems = 'claude_desktop_config.json', 'developer_settings.json', 'Claude Extensions',
  'Claude Extensions Settings', 'claude-code-sessions', 'local-agent-mode-sessions',
  'ccd-session-presets.json', 'ssh_configs.json', 'git-worktrees.json', 'mcp-user-tool-toggles.json',
  'extensions-installations.json', 'cowork-enabled-cli-ops.json' |
  ForEach-Object { "Claude/$_" } | Where-Object { Test-Path (Join-Path $env:APPDATA $_) }

$added = New-Object Collections.Generic.List[string]
$skipped = New-Object Collections.Generic.List[string]

function Add-File([string]$path, [string]$rel) {
  try {
    $src = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite, Delete')   # also reads files another app holds open
    try {
      $entry = $archive.CreateEntry($rel, [IO.Compression.CompressionLevel]::Fastest)
      try { $entry.LastWriteTime = [IO.File]::GetLastWriteTime($path) } catch {}   # zip cannot store dates before 1980
      $out = $entry.Open()
      try { $src.CopyTo($out) } finally { $out.Dispose() }
    } finally { $src.Dispose() }
    $added.Add($rel)
  } catch { $skipped.Add("$rel - $($_.Exception.GetBaseException().Message.Trim())") }
}

function Add-Tree([IO.DirectoryInfo]$dir, [string]$rel) {
  try { $children = $dir.GetFileSystemInfos() }
  catch { $skipped.Add("$rel/ - folder not read: $($_.Exception.GetBaseException().Message)"); return }
  foreach ($c in $children) {
    $r = "$rel/$($c.Name)"
    if ($excludes -contains $r) { continue }
    # Links are followed and stored as real files: skill folders are often junctions into ~\.agents\skills.
    # ponytail: only a link to its own parent folder is caught; a two-link cycle (A->B->A) would recurse until the path is too long.
    if ($c.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      $target = @((Get-Item -LiteralPath $c.FullName -Force).Target)[0]
      if ($target -and $c.FullName.StartsWith($target.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $skipped.Add("$r - link to its own parent folder $target, not followed"); continue
      }
    }
    if ($c -is [IO.DirectoryInfo]) { Add-Tree $c $r } else { Add-File $c.FullName $r }
  }
}

function Add-Root([string]$base, [string]$rel) {
  $p = Join-Path $base $rel
  if (Test-Path -LiteralPath $p -PathType Container) { Add-Tree ([IO.DirectoryInfo]$p) $rel } else { Add-File $p $rel }
}

# restore.ps1 reads this to warn when the new laptop has a different user path
$manifest = Join-Path $env:TEMP 'claude-backup-manifest.json'
@{ user = $env:USERNAME; profile = $env:USERPROFILE; computer = $env:COMPUTERNAME; date = (Get-Date -Format o) } |
  ConvertTo-Json | Set-Content $manifest -Encoding utf8

Write-Host "Writing $zip (several GB can take 10+ minutes)..."
$stream = [IO.File]::Open($zip, 'CreateNew')
$archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($i in $homeItems) { Add-Root $env:USERPROFILE $i }
  foreach ($i in $deskItems) { Add-Root $env:APPDATA $i }
  Add-File $manifest 'claude-backup-manifest.json'
} finally { $archive.Dispose(); $stream.Dispose() }   # Dispose writes the zip's index

$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllLines((Join-Path $Dest "$name.files.txt"), [string[]]$added, $utf8)
if (-not $skipped.Count) { $skipped.Add('No files skipped.') }
[IO.File]::WriteAllLines((Join-Path $Dest "$name.skipped.txt"), [string[]]$skipped, $utf8)

# Check: re-open the finished zip. It must hold the two files a restore cannot work without,
# and the same number of entries as the receipt.
$check = [IO.Compression.ZipFile]::OpenRead($zip)
try { $names = @($check.Entries | ForEach-Object { $_.FullName }) } finally { $check.Dispose() }
foreach ($must in '.claude/settings.json', '.claude.json') {
  if ($names -notcontains $must) { throw "Backup check failed: $must is not in $zip" }
}
if ($names.Count -ne $added.Count) { Write-Warning "Zip has $($names.Count) entries, receipt lists $($added.Count). A file failed part-way; see $name.skipped.txt" }
if ($skipped[0] -ne 'No files skipped.') { Write-Warning "$($skipped.Count) items skipped. See $(Join-Path $Dest "$name.skipped.txt")" }
"{0} - {1:N0} MB, {2:N0} files, {3} skipped. Receipts: {4}.files.txt, {4}.skipped.txt" -f
  $zip, ((Get-Item $zip).Length / 1MB), $added.Count, $(if ($skipped[0] -eq 'No files skipped.') { 0 } else { $skipped.Count }), $name
