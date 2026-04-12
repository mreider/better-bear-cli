#!/usr/bin/env bash
# daily-note.sh — Create a daily note from template
# Usage: ./daily-note.sh [tag]
# Skips if today's note already exists.
set -euo pipefail

TAG="${1:-daily}"
TODAY=$(date +%Y-%m-%d)
DOW=$(date +%A)
TITLE="$TODAY — $DOW"

# Check if today's note exists
EXISTS=$(bcli search "$TITLE" --json --no-sync 2>/dev/null | python3 -c "
import sys, json
notes = json.load(sys.stdin)
print('yes' if any(n['title'] == '$TITLE' for n in notes) else 'no')
" 2>/dev/null || echo "no")

if [ "$EXISTS" = "yes" ]; then
  echo "Today's note already exists: $TITLE"
  exit 0
fi

BODY="## Tasks
- [ ]

## Notes


## End of day
"

bcli create "$TITLE" --body "$BODY" --tags "$TAG" --fm "date=$TODAY" "type=daily" --json | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Created: {d[\"title\"]} ({d[\"id\"]})')"
