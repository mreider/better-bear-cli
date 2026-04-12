# Example Scripts

Ready-to-use shell scripts for common Bear workflows. Each script uses `bcli` with `--json` output — no dependencies beyond standard macOS tools and Python 3.

## Scripts

| Script | Description |
|--------|-------------|
| `daily-note.sh` | Create a daily note from template (skips if exists) |
| `meeting-note.sh` | Quick meeting note with attendees and action items |
| `backup.sh` | Export all notes + git commit (cron-friendly) |
| `cleanup-empty.sh` | Find and optionally trash empty/untitled notes |
| `find-duplicates.sh` | Find notes with duplicate titles |
| `bulk-tag.sh` | Add a tag to all notes matching a search |
| `stale-notes.sh` | Find notes not modified in N days |
| `weekly-review.sh` | Summary of notes modified this week |
| `import-markdown.sh` | Import a folder of markdown files as notes |
| `note-stats.sh` | Stats about your Bear library |

## Usage

```bash
# Make executable
chmod +x scripts/*.sh

# Run any script
./scripts/daily-note.sh
./scripts/meeting-note.sh "Sprint Planning" "Alice, Bob"
./scripts/backup.sh ~/bear-backup
./scripts/note-stats.sh
```

## Requirements

- `bcli` installed and authenticated (`bcli auth`)
- Python 3 (included on macOS)
- `git` (for backup.sh only)
