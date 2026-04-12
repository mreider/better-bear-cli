#!/usr/bin/env bash
# bulk-tag.sh — Add a tag to all notes matching a search query
# Usage: ./bulk-tag.sh "search term" "tag-to-add"
set -euo pipefail

QUERY="${1:?Usage: bulk-tag.sh \"search term\" \"tag-to-add\"}"
TAG="${2:?Provide tag as second argument}"

echo "Searching for notes matching: $QUERY"

bcli search "$QUERY" --json --limit 100 2>/dev/null | python3 -c "
import sys, json, subprocess

notes = json.load(sys.stdin)
print(f'Found {len(notes)} notes. Adding tag \"$TAG\"...\n')

for n in notes:
    nid = n['id']
    title = n['title']
    result = subprocess.run(
        ['bcli', 'tag', 'add', nid, '$TAG', '--json'],
        capture_output=True, text=True
    )
    try:
        d = json.loads(result.stdout)
        if d.get('added'):
            print(f'  + {title}')
        else:
            print(f'  - {title} (already tagged)')
    except:
        print(f'  ! {title} (error)')

print('\nDone.')
"
