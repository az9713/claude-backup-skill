# claude-backup-skill

A [Claude Code](https://claude.com/claude-code) skill that backs up the Claude Code and Claude Desktop setup on Windows into one zip file, and restores that zip on a new laptop.

**Full explanation (live page):** https://az9713.github.io/claude-backup-skill/

The page describes what the skill does, how the scripts work, what is left out of the backup and why, and why the files in the zip are enough to recreate the setup.

## What it backs up

- `%USERPROFILE%\.claude\`: settings, `CLAUDE.md`, skills, agents, commands, hooks, plugins, session transcripts, auto memory, prompt history, rewind checkpoints, login token.
- `%USERPROFILE%\.claude.json` (user MCP servers and per-project settings) and `%USERPROFILE%\AGENTS.md`.
- `%APPDATA%\Claude\`: the Desktop config, extensions, Claude Code sessions started from Desktop, and Cowork sessions.

It leaves out caches, logs, the Cowork VM image (`vm_bundles`, about 10 GB, downloaded again), program files, and Desktop login data that Windows encrypts to the old machine.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in)
- `robocopy` (built in), used only by the restore

## Install

Copy the `backup-claude` folder into your skills folder:

```powershell
Copy-Item -Recurse backup-claude "$env:USERPROFILE\.claude\skills\"
```

Then say "backup claude" to Claude Code, or run the script yourself.

## Back up

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\backup-claude\scripts\backup.ps1" -Dest D:\backups\claude
```

`-Dest` defaults to `D:\backups\claude`. The script creates the folder if it does not exist. Claude Code can stay open during the backup.

Each run writes three files:

| File | Content |
|---|---|
| `claude-backup-<COMPUTER>-<yyyyMMdd-HHmm>.zip` | The backup |
| `….files.txt` | Every file written into the zip |
| `….skipped.txt` | Each file or folder that an error kept out, with the reason, or `No files skipped.` |

After it writes the zip, the script opens it again. It stops with an error if `.claude/settings.json` or `.claude.json` is missing.

## Restore on a new laptop

1. Install Claude Code and Claude Desktop.
2. Close both apps. Open a plain PowerShell window. Do not run the restore from Claude Code.
3. Copy `restore.ps1` out of the zip (`.claude/skills/backup-claude/scripts/restore.ps1`).
4. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File restore.ps1 -Zip D:\backups\claude\claude-backup-OLDPC-20261017-1200.zip
   ```
5. Start Claude Code. If it asks you to log in, run `/login`. Log in to Claude Desktop again.

The restore merges the backup into the existing folders. Before it replaces an item, it copies the current version to `%USERPROFILE%\claude-pre-restore-<stamp>\`.

## Cautions

- **The zip is not encrypted.** It holds your Claude login token and any API keys in your MCP server settings. Keep it on a local or external drive. Do not upload it to cloud storage.
- **Install the MCP server programs again.** The zip holds the MCP server settings, not the programs they start (for example Node.js, uv, Bun, Python environments).
- **Use the same Windows user name.** Session folders and many paths in the config contain `C:\Users\<user>`. If the new profile path is different, the restore shows a warning, and you must change the paths yourself.
- **Not in the zip:** project-level `.claude\` folders and `.mcp.json` files (they move with each project), the source folders of local plugin marketplaces, and claude.ai web chats (use claude.ai → Settings → Privacy → Export data).

## Why not tar.exe

The first version used the Windows `tar.exe` (bsdtar 3.8.9). After one unreadable link, it silently left out the rest of that folder: 615 files in one real backup. It also crashed on a non-ASCII file name. The scripts now use the .NET zip classes and record every file in a receipt. The [live page](https://az9713.github.io/claude-backup-skill/) has the details.

## License

[MIT](LICENSE)
