# Scripts

Shell scripts for common Bear workflows. Each uses `bcli` with `--json` output — no dependencies beyond standard macOS tools and Python 3.

For library stats, duplicates, and health checks, use the built-in commands instead: `bcli stats`, `bcli duplicates`, `bcli health`.

| Script | Description |
|--------|-------------|
| `daily-note.sh` | Create a daily note from template (skips if exists) |
| `meeting-note.sh` | Meeting note with attendees and action items |
| `backup.sh` | Export all notes + git commit (cron-friendly) |
| `cleanup-empty.sh` | Find and optionally trash empty/untitled notes |
| `bulk-tag.sh` | Add a tag to all notes matching a search |
| `stale-notes.sh` | Find notes not modified in N days |
| `weekly-review.sh` | Summary of notes modified this week |
| `import-markdown.sh` | Import a folder of markdown files as notes |

## Usage

```bash
chmod +x scripts/*.sh
./scripts/daily-note.sh
./scripts/meeting-note.sh "Sprint Planning" "Alice, Bob"
./scripts/backup.sh ~/bear-backup
```

## Requirements

- `bcli` installed and authenticated (`bcli auth`)
- Python 3 (included on macOS)
- `git` (for backup.sh only)
