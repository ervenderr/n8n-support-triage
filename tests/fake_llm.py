"""Fake OpenAI-compatible LLM that returns MALFORMED classification JSON, to test the retry/fallback path.
Messages containing [bad-then-good] get garbage once, then valid JSON; all others always get garbage."""
import http.server, json
seen = {}
def reply(content): return json.dumps({"choices": [{"message": {"content": content}}]}).encode()
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        system, user = req["messages"][0]["content"], req["messages"][-1]["content"]
        if "first-draft replies" in system: out = "Thanks for reaching out. (fake draft)"
        else:
            key = user.split('Customer message:')[-1]  # same message across the retry prefix
            seen[key] = seen.get(key, 0) + 1
            out = ('{"category": "Billing", "confidence": 0.93, "needs_human_review": false, "reason": "ok on retry"}'
                   if "[bad-then-good]" in user and seen[key] > 1 else 'Sure! Here is the category: Billing {confidence: high')
        print("fake-llm call", "draft" if "first-draft" in system else f"classify#{seen.get(key)}", flush=True)
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(reply(out))
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("0.0.0.0", 9998), H).serve_forever()
