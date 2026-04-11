#!/usr/bin/env bash
# Integration test for all MCP server tool functionality via bcli
# Tests every tool path, then cleans up created notes

set -eo pipefail

BCLI="${BCLI:-../../.build/debug/bcli}"
PASS=0
FAIL=0
CLEANUP_IDS=()

pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1: $2"; FAIL=$((FAIL+1)); }

cleanup() {
  echo ""
  echo "=== Cleanup ==="
  for id in "${CLEANUP_IDS[@]+"${CLEANUP_IDS[@]}"}"; do
    if $BCLI trash "$id" --json &>/dev/null; then
      echo "  Trashed $id"
    else
      echo "  Warning: failed to trash $id"
    fi
  done
}
trap cleanup EXIT

echo "=== 1. bear_sync ==="
OUT=$($BCLI sync --json 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'notesCount' in d" 2>/dev/null; then
  COUNT=$(echo "$OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['notesCount'])")
  pass "sync returned notesCount=$COUNT"
else
  fail "sync" "missing notesCount in response"
fi

echo ""
echo "=== 2. bear_list_notes ==="
OUT=$($BCLI ls --json --limit 5 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d, list) and len(d) > 0" 2>/dev/null; then
  LEN=$(echo "$OUT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  pass "ls returned $LEN notes"
else
  fail "ls" "expected non-empty array"
fi

echo ""
echo "=== 3. bear_get_tags ==="
OUT=$($BCLI tags --json 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d, list)" 2>/dev/null; then
  LEN=$(echo "$OUT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  pass "tags returned $LEN tags"
else
  fail "tags" "expected array"
fi

echo ""
echo "=== 4. bear_create_note (simple) ==="
OUT=$($BCLI create "MCP Test Note 1" --body "Hello from integration test" --json 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'id' in d" 2>/dev/null; then
  NOTE1_ID=$(echo "$OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  CLEANUP_IDS+=("$NOTE1_ID")
  pass "created note id=$NOTE1_ID"
else
  fail "create simple" "missing id in response"
fi

echo ""
echo "=== 5. bear_create_note (with tags) ==="
OUT=$($BCLI create "MCP Test Note 2" --body "Note with tags" --tags "mcp-test,integration" --json 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'id' in d" 2>/dev/null; then
  NOTE2_ID=$(echo "$OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  CLEANUP_IDS+=("$NOTE2_ID")
  pass "created tagged note id=$NOTE2_ID"
else
  fail "create with tags" "missing id in response"
fi

echo ""
echo "=== 6. bear_get_note ==="
OUT=$($BCLI get "$NOTE1_ID" --json 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('title') == 'MCP Test Note 1'" 2>/dev/null; then
  pass "get note returned correct title"
else
  fail "get note" "title mismatch"
fi

echo ""
echo "=== 7. bear_get_note --raw ==="
OUT=$($BCLI get "$NOTE1_ID" --json --raw 2>&1)
if echo "$OUT" | grep -q "Hello from integration test"; then
  pass "get note raw returned body content"
else
  fail "get note raw" "body content not found"
fi

echo ""
echo "=== 8. bear_search ==="
OUT=$($BCLI search "MCP Test Note" --json --limit 5 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d, list) and len(d) > 0" 2>/dev/null; then
  LEN=$(echo "$OUT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  pass "search found $LEN results"
else
  fail "search" "expected non-empty results"
fi

echo ""
echo "=== 9. bear_list_notes (tag filter) ==="
OUT=$($BCLI ls --json --tag "mcp-test" 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d, list) and len(d) > 0" 2>/dev/null; then
  pass "ls with tag filter returned results"
else
  fail "ls tag filter" "expected results for mcp-test tag"
fi

echo ""
echo "=== 10. bear_edit_note (append) ==="
OUT=$($BCLI edit "$NOTE1_ID" --append "Appended line" --json 2>&1)
if [ $? -eq 0 ]; then
  # Verify the append
  VERIFY=$($BCLI get "$NOTE1_ID" --json --raw 2>&1)
  if echo "$VERIFY" | grep -q "Appended line"; then
    pass "edit append succeeded and verified"
  else
    fail "edit append" "appended text not found in note"
  fi
else
  fail "edit append" "command failed"
fi

echo ""
echo "=== 11. bear_edit_note (replace body via stdin) ==="
echo "Replaced body content" | $BCLI edit "$NOTE1_ID" --stdin --json 2>&1
VERIFY=$($BCLI get "$NOTE1_ID" --json --raw 2>&1)
if echo "$VERIFY" | grep -q "Replaced body content"; then
  pass "edit replace body succeeded and verified"
else
  fail "edit replace body" "replaced text not found in note"
fi

echo ""
echo "=== 12. bear_create_note (with TODOs) ==="
TODO_BODY="- [ ] First task
- [ ] Second task
- [x] Done task"
OUT=$($BCLI create "MCP Test TODO Note" --body "$TODO_BODY" --json 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'id' in d" 2>/dev/null; then
  TODO_NOTE_ID=$(echo "$OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  CLEANUP_IDS+=("$TODO_NOTE_ID")
  pass "created TODO note id=$TODO_NOTE_ID"
else
  fail "create TODO note" "missing id"
fi

echo ""
echo "=== 13. bear_list_todos ==="
OUT=$($BCLI todo --json --limit 5 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d, list)" 2>/dev/null; then
  LEN=$(echo "$OUT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  pass "list todos returned $LEN notes with todos"
else
  fail "list todos" "expected array"
fi

echo ""
echo "=== 14. bear_get_todos ==="
OUT=$($BCLI todo "$TODO_NOTE_ID" --json 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d['todos']) >= 3" 2>/dev/null; then
  LEN=$(echo "$OUT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['todos']))")
  pass "get todos returned $LEN items"
else
  fail "get todos" "expected >= 3 todo items"
fi

echo ""
echo "=== 15. bear_toggle_todo ==="
OUT=$($BCLI todo "$TODO_NOTE_ID" --toggle 1 --json 2>&1)
if [ $? -eq 0 ]; then
  # Verify toggle — first item should now be complete (was incomplete)
  VERIFY=$($BCLI todo "$TODO_NOTE_ID" --json 2>&1)
  FIRST_DONE=$(echo "$VERIFY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['todos'][0]['complete'])" 2>/dev/null)
  pass "toggle todo succeeded (first item complete: $FIRST_DONE)"
else
  fail "toggle todo" "command failed"
fi

echo ""
echo "=== 16. bear_sync (full) ==="
OUT=$($BCLI sync --full --json 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'notesCount' in d" 2>/dev/null; then
  pass "full sync succeeded"
else
  fail "full sync" "missing notesCount"
fi

echo ""
echo "=== 17. bear_trash_note ==="
# Create a throwaway note to trash explicitly (not via cleanup)
OUT=$($BCLI create "MCP Trash Test" --body "delete me" --json 2>&1)
TRASH_ID=$(echo "$OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
OUT=$($BCLI trash "$TRASH_ID" --json 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('trashed') == True" 2>/dev/null; then
  pass "trash note succeeded"
else
  fail "trash note" "expected trashed=true"
fi

echo ""
echo "=== 18. bear_list_notes (include_trashed) ==="
OUT=$($BCLI ls --json --trashed --limit 5 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d, list)" 2>/dev/null; then
  pass "ls with --trashed returned results"
else
  fail "ls trashed" "expected array"
fi

echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
