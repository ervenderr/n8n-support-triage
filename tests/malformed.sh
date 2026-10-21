#!/usr/bin/env bash
# Deploys a COPY of the workflow wired to tests/fake_llm.py (port 9998) on path /support-message-fakellm, then runs the malformed-JSON samples.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json
w = json.load(open("workflow.json"))
w["id"], w["name"] = "triageFake01", "TEST COPY (fake malformed LLM)"
for n in w["nodes"]:
    if n["type"].endswith(".webhook"): n["parameters"]["path"] = "support-message-fakellm"; n["webhookId"] = "support-message-fakellm"
    if n["name"].startswith("Config"):
        for a in n["parameters"]["assignments"]["assignments"]:
            if a["name"] == "llmBaseUrl": a["value"] = "http://host.docker.internal:9998"
json.dump(w, open(".fake.tmp.json", "w"))
PY
C=$(docker compose ps -q n8n)
docker cp .fake.tmp.json "$C:/tmp/fake.json"; rm -f .fake.tmp.json
docker compose exec -T n8n n8n import:workflow --input=/tmp/fake.json >/dev/null
docker compose exec -T n8n n8n publish:workflow --id=triageFake01 >/dev/null
docker compose restart n8n >/dev/null; sleep 15
(python3 tests/fake_llm.py & echo $! > .fake.pid); sleep 1
python3 tests/run.py --with-fake-llm || true
kill "$(cat .fake.pid)"; rm -f .fake.pid
