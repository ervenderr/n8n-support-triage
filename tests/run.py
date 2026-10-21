"""Posts every message in sample-messages.json to the webhook and checks the expectation. Usage: python3 tests/run.py            (real LLM samples)
       python3 tests/run.py --with-fake-llm  (malformed-JSON samples; needs tests/malformed.sh first)
Sleeps between calls to stay inside the Gemini free-tier rate limit."""
import json, pathlib, sys, time, urllib.request, urllib.error
URL = "http://localhost:5690/webhook/support-message"
samples = json.loads(pathlib.Path(__file__).with_name("..").joinpath("sample-messages.json").resolve().read_text())
FAKE = "--with-fake-llm" in sys.argv
fails = 0
for s in samples:
    if bool(s.get("needs_fake_llm")) != FAKE:
        continue
    url = URL.replace("support-message", "support-message-fakellm") if FAKE else URL
    req = urllib.request.Request(url, json.dumps(s["payload"]).encode(), {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as r: code, body = r.status, json.loads(r.read())
    except urllib.error.HTTPError as e: code, body = e.code, json.loads(e.read() or b"{}")
    exp = s["expect"]
    bad = [k for k in ("duplicate", "category", "notified") if k in exp and body.get(k) != exp[k]]
    if code != exp["http"]: bad.append("http")
    fails += bool(bad)
    shown = {k: body.get(k) for k in ("duplicate", "id", "status", "category", "confidence", "needs_human_review", "notified", "ai_attempts", "error")}
    print(("PASS" if not bad else "FAIL " + str(bad)), s["name"], code, json.dumps({k: v for k, v in shown.items() if v is not None}))
    time.sleep(4)
sys.exit(1 if fails else 0)
