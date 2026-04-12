#!/usr/bin/env bash
# stale-notes.sh — Find notes not modified in N days
# Usage: ./stale-notes.sh [days]            # list stale notes (default: 90)
#        ./stale-notes.sh [days] --archive  # archive them
set -euo pipefail

DAYS="${1:-90}"
ACTION="${2:-}"
CUTOFF=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "$DAYS days ago" +%Y-%m-%d)

echo "Notes not modified since $CUTOFF ($DAYS days):"
echo ""

bcli ls --all --json 2>/dev/null | python3 -c "
import sys, json
from datetime import datetime, timezone

notes = json.load(sys.stdin)
cutoff = datetime.fromisoformat('${CUTOFF}T00:00:00+00:00')

stale = []
for n in notes:
    mod = n.get('modificationDate', 0)
    if isinstance(mod, (int, float)) and mod > 0:
        mod_dt = datetime.fromtimestamp(mod, tz=timezone.utc)
    elif isinstance(mod, str):
        mod_dt = datetime.fromisoformat(mod.replace('Z', '+00:00'))
    else:
        continue
    if mod_dt < cutoff:
        stale.append((n['id'], n.get('title', '(untitled)'), mod_dt.strftime('%Y-%m-%d')))

if not stale:
    print('No stale notes found.')
    sys.exit(0)

print(f'Found {len(stale)} stale notes:\n')
for nid, title, mod in sorted(stale, key=lambda x: x[2]):
    print(f'  {nid}  {mod}  {title}')
" 2>/dev/null

if [ "$ACTION" = "--archive" ]; then
  echo ""
  echo "Archiving stale notes..."
  bcli ls --all --json 2>/dev/null | python3 -c "
import sys, json, subprocess
from datetime import datetime, timezone

notes = json.load(sys.stdin)
cutoff = datetime.fromisoformat('${CUTOFF}T00:00:00+00:00')

for n in notes:
    mod = n.get('modificationDate', 0)
    if isinstance(mod, (int, float)) and mod > 0:
        mod_dt = datetime.fromtimestamp(mod, tz=timezone.utc)
    elif isinstance(mod, str):
        mod_dt = datetime.fromisoformat(mod.replace('Z', '+00:00'))
    else:
        continue
    if mod_dt < cutoff:
        subprocess.run(['bcli', 'archive', n['id'], '--json'], capture_output=True)
        print(f'  Archived: {n.get(\"title\", \"?\")}')" 2>/dev/null
fi
