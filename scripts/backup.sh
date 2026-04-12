#!/usr/bin/env bash
# backup.sh — Export all notes and commit to a git repo
# Usage: ./backup.sh [backup-dir]
# Run on a cron for automatic versioned backups:
#   0 2 * * * /path/to/backup.sh ~/bear-backup
set -euo pipefail

BACKUP_DIR="${1:-$HOME/bear-backup}"
NOTES_DIR="$BACKUP_DIR/notes"
DATE=$(date +%Y-%m-%d_%H%M)

mkdir -p "$NOTES_DIR"

# Init git repo if needed
if [ ! -d "$BACKUP_DIR/.git" ]; then
  git -C "$BACKUP_DIR" init
  echo "Initialized backup repo at $BACKUP_DIR"
fi

# Sync and export
bcli sync --json > /dev/null 2>&1
bcli export "$NOTES_DIR" --frontmatter --by-tag 2>/dev/null

# Count exported files
COUNT=$(find "$NOTES_DIR" -name "*.md" | wc -l | tr -d ' ')

# Commit
cd "$BACKUP_DIR"
git add -A
if git diff --cached --quiet; then
  echo "No changes to back up ($COUNT notes)"
else
  git commit -m "Backup $DATE — $COUNT notes" --quiet
  echo "Backed up $COUNT notes ($DATE)"
fi
