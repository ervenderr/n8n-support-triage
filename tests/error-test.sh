#!/usr/bin/env bash
# Fault injection: break the "Save Result" step by renaming a column, send a message, expect HTTP 500 JSON error, status=failed + alert; then fix and re-send to prove recovery.
cd "$(dirname "$0")/.."
SQL() { docker compose exec -T postgres psql -U triage -d triage -c "$1"; }
MSG='{"message_id":"t-err-1","sender":"hal@example.com","text":"How do I change the email address on my account?"}'
SQL "ALTER TABLE support_messages RENAME COLUMN draft_response TO draft_response_x" >/dev/null
echo "--- send with broken DB:"
OUT=$(curl -s -m 120 -w '\n%{http_code}' -XPOST localhost:5690/webhook/support-message -H 'content-type: application/json' -d "$MSG")
echo "$OUT"
[ "$(echo "$OUT" | tail -1)" = 500 ] && echo "$OUT" | head -1 | grep -q '"status":"error"' && echo "PASS: HTTP 500 + JSON error" || echo "FAIL: expected 500 + JSON error"
sleep 3; SQL "select id,message_id,status,left(error,90) error from support_messages where message_id='t-err-1'"
echo "--- team alert:"; tail -1 tests/notify.log | cut -c1-250
SQL "ALTER TABLE support_messages RENAME COLUMN draft_response_x TO draft_response" >/dev/null
echo "--- re-send after fix (also the happy-path check):"; curl -s -m 120 -XPOST localhost:5690/webhook/support-message -H 'content-type: application/json' -d "$MSG" | cut -c1-200; echo
SQL "select id,message_id,category,status,error from support_messages where message_id='t-err-1'"
