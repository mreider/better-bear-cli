#!/usr/bin/env bash
# note-stats.sh — Stats about your Bear library
# Usage: ./note-stats.sh
set -euo pipefail

echo "=== Bear Library Stats ==="
echo ""

# Sync first
bcli sync --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Synced: {d[\"notesCount\"]} notes')" 2>/dev/null
echo ""

# Notes stats
bcli ls --all --json 2>/dev/null | python3 -c "
import sys, json
from datetime import datetime, timezone

notes = json.load(sys.stdin)
print(f'Total notes: {len(notes)}')

pinned = sum(1 for n in notes if n.get('pinned'))
print(f'Pinned: {pinned}')

# Tags
all_tags = set()
tagged = 0
for n in notes:
    tags = n.get('tags', [])
    if tags:
        tagged += 1
        all_tags.update(tags)
print(f'Tagged: {tagged}')
print(f'Untagged: {len(notes) - tagged}')
print(f'Unique tags: {len(all_tags)}')

# Dates
dates = []
for n in notes:
    mod = n.get('modificationDate', 0)
    if isinstance(mod, (int, float)) and mod > 0:
        dates.append(datetime.fromtimestamp(mod, tz=timezone.utc))

if dates:
    newest = max(dates).strftime('%Y-%m-%d')
    oldest = min(dates).strftime('%Y-%m-%d')
    print(f'Oldest note: {oldest}')
    print(f'Newest note: {newest}')

# Most used tags
from collections import Counter
tag_counts = Counter()
for n in notes:
    for t in n.get('tags', []):
        tag_counts[t] += 1

if tag_counts:
    print()
    print('Top 10 tags:')
    for tag, count in tag_counts.most_common(10):
        print(f'  #{tag}: {count} notes')
" 2>/dev/null

echo ""

# Archived and trashed
ARCHIVED=$(bcli ls --archived --all --json 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
TRASHED=$(bcli ls --trashed --all --json 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "Archived: $ARCHIVED"
echo "Trashed: $TRASHED"

# TODOs
TODOS=$(bcli todo --json --no-sync 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "Notes with open TODOs: $TODOS"
