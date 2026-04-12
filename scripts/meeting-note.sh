#!/usr/bin/env bash
# meeting-note.sh — Create a meeting note with attendees
# Usage: ./meeting-note.sh "Meeting Title" "Alice, Bob, Carol" [tag]
set -euo pipefail

TITLE="${1:?Usage: meeting-note.sh \"Title\" \"Attendees\" [tag]}"
ATTENDEES="${2:?Provide attendees as second argument}"
TAG="${3:-meetings}"
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)

BODY="## Attendees
$(echo "$ATTENDEES" | tr ',' '\n' | sed 's/^ */- /')

## Agenda


## Discussion


## Action Items
- [ ]

## Decisions
"

bcli create "$TITLE" --body "$BODY" --tags "$TAG" \
  --fm "date=$DATE" "time=$TIME" "type=meeting" "attendees=$ATTENDEES" --json | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Created: {d[\"title\"]} ({d[\"id\"]})')"
