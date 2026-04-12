#!/usr/bin/env bash
# health-check.sh — Report on the health of your Bear notes library
# Usage: ./health-check.sh            # summary
#        ./health-check.sh --details  # show individual items
set -euo pipefail

DETAILS="${1:-}"

bcli sync --json > /dev/null 2>&1

echo "=== Bear Health Report ==="
echo ""

bcli health --json 2>/dev/null | python3 -c "
import sys, json

d = json.load(sys.stdin)
details = '--details' in sys.argv

issues = 0

def report(icon, count, label, items_key=None):
    global issues
    if count > 0:
        if icon == '⚠':
            issues += 1
        print(f'{icon}  {count} {label}')
        if details and items_key and items_key in d:
            for item in d[items_key][:20]:
                if isinstance(item, dict):
                    print(f'    {item.get(\"id\",\"\")}  {item.get(\"title\",\"\")}')
                else:
                    print(f'    {item}')
            if len(d.get(items_key, [])) > 20:
                print(f'    ... and {len(d[items_key]) - 20} more')
            print()
    else:
        print(f'✓  No {label}')

report('⚠', d.get('duplicateTitles', 0), 'duplicate titles', 'duplicates')
report('⚠', d.get('emptyNotes', 0), 'empty/untitled notes', 'emptyList')
report('⚠', d.get('trashedOver30Days', 0), 'notes in trash for 30+ days', 'trashedList')
report('⚠', d.get('conflictedNotes', 0), 'conflicted notes (sync conflicts)', 'conflictedList')
report('ℹ', d.get('untaggedNotes', 0), 'untagged notes')
report('ℹ', d.get('orphanedTags', 0), 'orphaned tags (0 notes)', 'orphanedTagsList')
report('ℹ', d.get('largeNotes', 0), 'notes over 50KB', 'largeList')

print()
print(f'{d.get(\"totalNotes\", 0)} notes, {d.get(\"totalTags\", 0)} tags')

if issues == 0:
    print('Everything looks good!')
" $DETAILS
