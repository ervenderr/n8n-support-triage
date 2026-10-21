#!/usr/bin/env bash
# Starts the throwaway stack, creates credentials at runtime (key never written into the workflow), imports + publishes workflows.
# Provider: LLM_PROVIDER in .env = gemini (default) | groq | openai | ollama, with the key in GEMINI_API_KEY / GROQ_API_KEY /
# OPENAI_API_KEY (or LLM_API_KEY for any). Ollama needs no key. The provider's URL and model are patched into a temp copy of workflow.json.
set -euo pipefail
cd "$(dirname "$0")"
docker compose up -d --wait postgres
docker compose up -d n8n
until curl -s -o /dev/null http://localhost:5690/healthz; do sleep 2; done  # wait for the server to finish its DB migrations before any CLI import touches the same DB

python3 - <<'PY'
import json, os
env = dict(l.strip().split("=", 1) for l in open(".env") if "=" in l and not l.startswith("#"))
PROVIDERS = {  # name: (base url, model, key variable)
  "gemini": ("https://generativelanguage.googleapis.com/v1beta/openai", "gemini-2.5-flash-lite", "GEMINI_API_KEY"),
  "groq": ("https://api.groq.com/openai/v1", "openai/gpt-oss-20b", "GROQ_API_KEY"),
  "openai": ("https://api.openai.com/v1", "gpt-4o-mini", "OPENAI_API_KEY"),
  "ollama": ("http://host.docker.internal:11434/v1", "llama3.1:8b", ""),
}
provider = env.get("LLM_PROVIDER", "gemini").lower()
if provider not in PROVIDERS:
    raise SystemExit(f"LLM_PROVIDER must be one of {', '.join(PROVIDERS)}")
base_url, model, key_var = PROVIDERS[provider]
key = env.get("LLM_API_KEY") or env.get(key_var) or ("ollama" if provider == "ollama" else "")
if not key:
    raise SystemExit(f"{key_var} (or LLM_API_KEY) is missing in .env")
wf = json.load(open("workflow.json"))
for node in wf["nodes"]:
    for a in node.get("parameters", {}).get("assignments", {}).get("assignments", []):
        if a["name"] == "llmBaseUrl": a["value"] = base_url
        if a["name"] == "llmModel": a["value"] = model
json.dump(wf, open(".workflow.tmp.json", "w"))
print(f"LLM provider: {provider} ({model})")
creds = [
  {"id": "llmKey01", "name": "LLM API Key", "type": "httpHeaderAuth", "data": {"name": "Authorization", "value": "Bearer " + key}},
  {"id": "pgTriage01", "name": "Triage Postgres", "type": "postgres",
   "data": {"host": "postgres", "port": 5432, "database": "triage", "user": "triage", "password": "triage_local_only", "ssl": "disable", "maxConnections": 5, "allowUnauthorizedCerts": False}},
]
json.dump(creds, open(".creds.tmp.json", "w"))
PY
C=$(docker compose ps -q n8n)
docker cp .creds.tmp.json "$C:/tmp/creds.json" && rm -f .creds.tmp.json
docker compose exec -T n8n n8n import:credentials --input=/tmp/creds.json
docker compose exec -T -u root n8n rm -f /tmp/creds.json
docker cp error-workflow.json "$C:/tmp/error-workflow.json"
docker cp demo-view.json "$C:/tmp/demo-view.json"
docker cp .workflow.tmp.json "$C:/tmp/workflow.json" && rm -f .workflow.tmp.json
docker compose exec -T n8n n8n import:workflow --input=/tmp/error-workflow.json
docker compose exec -T n8n n8n import:workflow --input=/tmp/workflow.json
docker compose exec -T n8n n8n import:workflow --input=/tmp/demo-view.json
docker compose exec -T n8n n8n publish:workflow --id=triageMain01
docker compose exec -T n8n n8n publish:workflow --id=triageErr01
docker compose exec -T n8n n8n publish:workflow --id=triageView01
docker compose restart n8n
until curl -s -o /dev/null http://localhost:5690/healthz; do sleep 2; done
sleep 8  # let published workflows register their webhooks
echo "n8n ready: http://localhost:5690  webhook: POST http://localhost:5690/webhook/support-message"

# Local login for the n8n UI: created once from N8N_OWNER_EMAIL / N8N_OWNER_PASSWORD in .env (generated and saved there if missing).
python3 - <<'PY'
import json, secrets, urllib.request
env = dict(l.strip().split("=", 1) for l in open(".env") if "=" in l and not l.startswith("#"))
email = env.get("N8N_OWNER_EMAIL", "owner@triage.local")
password = env.get("N8N_OWNER_PASSWORD") or "Tr1-" + secrets.token_urlsafe(12)  # n8n needs 8+ chars, a digit and a capital
if "N8N_OWNER_PASSWORD" not in env:
    open(".env", "a").write(f"\nN8N_OWNER_EMAIL={email}\nN8N_OWNER_PASSWORD={password}\n")
req = urllib.request.Request("http://localhost:5690/rest/owner/setup", method="POST", headers={"content-type": "application/json"},
    data=json.dumps({"email": email, "firstName": "Triage", "lastName": "Owner", "password": password}).encode())
try:
    urllib.request.urlopen(req)
    print("n8n login created: see N8N_OWNER_EMAIL / N8N_OWNER_PASSWORD in .env")
except Exception as e:  # already set up on a previous run
    print("n8n owner already exists or setup failed:", e)
PY
