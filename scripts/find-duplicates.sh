#!/usr/bin/env bash
# find-duplicates.sh — Find notes with duplicate titles
# Usage: ./find-duplicates.sh
set -euo pipefail

bcli sync --json > /dev/null 2>&1

bcli ls --all --json 2>/dev/null | python3 -c "
import sys, json
from collections import Counter

notes = json.load(sys.stdin)
titles = Counter(n.get('title', '') for n in notes if n.get('title'))
dupes = {t: c for t, c in titles.items() if c > 1}

if not dupes:
    print('No duplicate titles found.')
    sys.exit(0)

print(f'Found {len(dupes)} duplicate titles:\n')
for title, count in sorted(dupes.items()):
    print(f'  \"{title}\" ({count} copies)')
    for n in notes:
        if n.get('title') == title:
            mod = n.get('modificationDate', 0)
            print(f'    {n[\"id\"]}  modified: {mod}')
    print()
"
