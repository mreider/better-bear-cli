#!/usr/bin/env bash
# import-markdown.sh — Import a folder of markdown files as Bear notes
# Usage: ./import-markdown.sh /path/to/markdown/files [tag]
# Preserves YAML front matter. Extracts title from # heading or filename.
set -euo pipefail

DIR="${1:?Usage: import-markdown.sh /path/to/files [tag]}"
TAG="${2:-}"
COUNT=0
ERRORS=0

for f in "$DIR"/*.md "$DIR"/*.markdown; do
  [ -f "$f" ] || continue

  FILENAME=$(basename "$f" | sed 's/\.\(md\|markdown\)$//')

  # Extract title from first # heading, or use filename
  TITLE=$(head -20 "$f" | grep -m1 '^# ' | sed 's/^# //' || echo "")
  if [ -z "$TITLE" ]; then
    TITLE="$FILENAME"
  fi

  # Read body (skip the title line if it exists)
  BODY=$(python3 -c "
import sys
lines = open('$f').readlines()
# Skip front matter + title
i = 0
if lines and lines[0].strip() == '---':
    for j in range(1, len(lines)):
        if lines[j].strip() == '---':
            i = j + 1
            break
while i < len(lines) and lines[i].strip().startswith('# '):
    i += 1
# Skip leading blank lines
while i < len(lines) and lines[i].strip() == '':
    i += 1
print(''.join(lines[i:]).rstrip())
" 2>/dev/null)

  ARGS=(create "$TITLE" --body "$BODY" --json)
  [ -n "$TAG" ] && ARGS+=(--tags "$TAG")

  if bcli "${ARGS[@]}" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  Imported: {d[\"title\"]}')" 2>/dev/null; then
    COUNT=$((COUNT + 1))
  else
    echo "  Error: $FILENAME"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
echo "Imported $COUNT notes ($ERRORS errors)"
