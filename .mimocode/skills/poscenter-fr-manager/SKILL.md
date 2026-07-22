# POScenter FR Manager - Development Skill

## Project Overview
PowerShell WinForms GUI application for connecting to Poscenter fiscal registers (FR) via SSH tunnel using plink.exe.

## Repository
- GitHub: https://github.com/dagmorport/poscenter-fr-manager
- Branch: main
- Current version: 1.0.0

## Architecture
- `app.ps1` — Main GUI (WinForms), auto-update on startup
- `connect.ps1` — CLI connection mode
- `disconnect.ps1` — CLI disconnect
- `update.ps1` — Auto-updater from GitHub
- `config.json` — Configuration template (placeholder IPs)
- `version.txt` — Current version tracking
- `run.bat` — Launcher (hides PowerShell console)

## Key Files Tracked in Git
```
.gitignore, README.md, app.ps1, connect.ps1, disconnect.ps1,
update.ps1, version.txt, config.json, kassas.txt, run.bat, icon.png
```

## Files Excluded from Git (in .gitignore)
- `test*.ps1`, `diagnose.ps1` — diagnostic/test files
- `copy-key.bat`, `generate-config.ps1`, `setup-key.ps1` — one-time setup
- `image/` — old screenshots
- `plan.md` — internal planning
- `logs/`, `pids/` — runtime data
- `plink.exe` — binary (user downloads separately)

## Config Structure
```json
{
  "fr_ip": "192.168.X.X",
  "fr_port": 7778,
  "local_port": 17778,
  "ssh_port": 22,
  "ssh_user": "root",
  "plink_path": "",
  "kassas": [
    {"name": "KASSA_1", "ip": "192.168.1.100"}
  ]
}
```

## Development Workflow
1. Edit files in working directory
2. Test with `run.bat`
3. Commit: `git add -A && git commit -m "description" && git push`
4. Bump `version.txt` for auto-update to trigger

## Auto-Update System
- Checks `raw.githubusercontent.com/dagmorport/poscenter-fr-manager/main/version.txt` on startup
- Compares semantic versions (x.y.z)
- Downloads updated files via `update.ps1`
- User confirms before updating

## Security Notes
- No hardcoded passwords in tracked files
- config.json uses placeholder IPs
- Passwords entered at runtime via GUI or Read-Host
