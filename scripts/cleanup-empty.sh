#!/usr/bin/env bash
# cleanup-empty.sh — Find and optionally trash empty/untitled notes
# Usage: ./cleanup-empty.sh          # list empty notes
#        ./cleanup-empty.sh --trash  # trash them
set -euo pipefail

TRASH="${1:-}"

bcli sync --json > /dev/null 2>&1

EMPTY=$(bcli ls --all --json 2>/dev/null | python3 -c "
import sys, json
notes = json.load(sys.stdin)
empty = []
for n in notes:
    title = n.get('title', '')
    if not title or title.strip() in ('', '# '):
        empty.append(n)
for n in empty:
    print(f'{n[\"id\"]}  {n.get(\"title\", \"(untitled)\")}')" 2>/dev/null)

if [ -z "$EMPTY" ]; then
  echo "No empty notes found."
  exit 0
fi

COUNT=$(echo "$EMPTY" | wc -l | tr -d ' ')
echo "Found $COUNT empty/untitled notes:"
echo "$EMPTY"

if [ "$TRASH" = "--trash" ]; then
  echo ""
  echo "Trashing..."
  echo "$EMPTY" | while read -r line; do
    ID=$(echo "$line" | awk '{print $1}')
    bcli trash "$ID" --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  Trashed: {d.get(\"title\",\"?\")}')"
  done
else
  echo ""
  echo "Run with --trash to delete them."
fi
