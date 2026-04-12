#!/usr/bin/env bash
# weekly-review.sh — Summary of notes modified this week
# Usage: ./weekly-review.sh
set -euo pipefail

echo "=== Weekly Review ==="
echo ""

bcli search "" --since last-week --json --limit 200 2>/dev/null | python3 -c "
import sys, json

notes = json.load(sys.stdin)

if not notes:
    print('No notes modified this week.')
    sys.exit(0)

print(f'Notes modified this week: {len(notes)}')
print()

# Group by match type
by_tag = {}
for n in notes:
    tags = n.get('tags', [])
    if tags:
        for t in tags:
            by_tag.setdefault(t, []).append(n)
    else:
        by_tag.setdefault('(untagged)', []).append(n)

for tag in sorted(by_tag.keys()):
    tag_notes = by_tag[tag]
    print(f'  #{tag} ({len(tag_notes)} notes)')
    for n in tag_notes[:5]:
        print(f'    - {n[\"title\"]}')
    if len(tag_notes) > 5:
        print(f'    ... and {len(tag_notes) - 5} more')
    print()
" 2>/dev/null
