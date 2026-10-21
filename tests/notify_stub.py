"""Local stand-in for a Slack incoming webhook. Prints and appends every POST to tests/notify.log."""
import http.server, json, pathlib
LOG = pathlib.Path(__file__).with_name("notify.log")
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        text = json.loads(body).get("text", body)
        LOG.open("a").write(text.replace("\n", " | ") + "\n"); print("NOTIFY:", text.replace("\n", " | "), flush=True)
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("0.0.0.0", 9999), H).serve_forever()
