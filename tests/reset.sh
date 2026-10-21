#!/usr/bin/env bash
# Empties the table so the sample set can be re-run (otherwise everything is correctly rejected as duplicate).
cd "$(dirname "$0")/.." && docker compose exec -T postgres psql -U triage -d triage -qc "TRUNCATE support_messages RESTART IDENTITY"
