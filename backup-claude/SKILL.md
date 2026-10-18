---
name: backup-claude
description: Back up all Claude Code and Claude Desktop setup, skills, plugins, memory, and session transcripts into one zip, and restore that zip on a new Windows laptop. Use when the user says "backup claude", "back up my claude setup", "migrate claude to a new laptop", "restore my claude backup", or asks what to copy to move Claude to another machine.
---

# backup-claude

Two PowerShell scripts in `scripts/`. Windows only. They use Windows PowerShell 5.1, the .NET zip classes (`System.IO.Compression`), and `robocopy`. Do not switch them to `tar.exe`: on 2026-10-17 bsdtar 3.8.9 crashed on non-ASCII file names, and after one unreadable entry it silently dropped the rest of that folder (613 Cowork session files).

## Back up (old laptop)

Run from any shell. Claude Code may stay open; a file locked by a running app is skipped with a warning.

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\backup-claude\scripts\backup.ps1"
```

`-Dest` defaults to `D:\backups\claude` (an external drive) and the script creates the folder if it is missing. If the drive has another letter, pass `-Dest <letter>:\backups\claude`. Output: `claude-backup-<COMPUTER>-<yyyyMMdd-HHmm>.zip`, plus two receipts next to it: `.files.txt` (every file written into the zip) and `.skipped.txt` (each file or folder that was left out by an error, with the reason, or `No files skipped.`). Files that another app holds open are still read. Links (symlinks, junctions) are followed and stored as real files, for example skill folders that are junctions into `~\.agents\skills`. After a restore they are plain folders, not links. Files locked exclusively, broken links, and a link to its own parent folder go into `.skipped.txt`. The script re-opens the finished zip: it fails if `.claude/settings.json` or `.claude.json` is missing, and warns if the zip's entry count differs from `.files.txt`. A full backup can be several GB and take minutes, so run it in the background from Claude Code.

## Restore (new laptop)

1. Install Claude Code and Claude Desktop.
2. Close both. The restore refuses to run while any `claude` process runs, so run it from a plain PowerShell window, not from Claude Code.
3. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File restore.ps1 -Zip D:\backups\claude\claude-backup-OLDPC-20261017-1200.zip
   ```
   Copy `restore.ps1` out of the zip first (`.claude/skills/backup-claude/scripts/restore.ps1`), or from wherever you keep it.
4. Start Claude Code. If it asks you to log in, run `/login`.

The restore merges into existing folders. Each item it overwrites is first copied to `%USERPROFILE%\claude-pre-restore-<stamp>\`.

## What is in the zip

| From | Kept | Left out |
|---|---|---|
| `%USERPROFILE%\.claude\` | everything else: settings, CLAUDE.md, skills, agents, commands, hooks, plugins, `projects\` (sessions + memory), `history.jsonl`, `file-history\`, plans, tasks | `cache`, `debug`, `shell-snapshots`, `paste-cache`, `telemetry`, `session-env`, `statsig`, `daemon.lock` |
| `%USERPROFILE%\` | `.claude.json` (user MCP servers, project state), `AGENTS.md` | — |
| `%APPDATA%\Claude\` | `claude_desktop_config.json`, `developer_settings.json`, `Claude Extensions`, `Claude Extensions Settings`, `claude-code-sessions`, `local-agent-mode-sessions`, and small JSON settings files | `vm_bundles` (~10 GB, re-downloaded), browser caches, logs, `config.json` and other login state that is encrypted to the old machine |

## Gotchas

- **Secrets.** The zip is not encrypted. It holds the login token (`.claude\.credentials.json`) and any API keys in MCP `env` blocks of `.claude.json` and `claude_desktop_config.json`. Keep it on a local drive, not in cloud storage.
- **Different user path.** Session folders (`.claude\projects\C--Users-<user>-...`) and paths in `settings.json`, `.claude.json`, and `claude_desktop_config.json` contain the old profile path. The restore warns when the path changes; fix the paths by hand.
- **MCP server programs.** The zip holds MCP server settings, not the programs they start (Node.js, uv, Bun, Python environments, app executables). Install those on the new laptop.
- **Not covered.** Project-level `.claude\`, `CLAUDE.md`, `.mcp.json` (they move with each project folder), the source folders of local (directory) plugin marketplaces, other personal folders outside `.claude`, and claude.ai web chats (export them at claude.ai → Settings → Privacy → Export data).
- **Old sessions.** Claude Code deletes transcripts older than `cleanupPeriodDays` (default 30). A backup holds only what exists on that day.
