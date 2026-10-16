#!/usr/bin/env python3
"""Serves the Clanker live dashboard and exposes a status endpoint that the
dashboard polls. The status file is written by clanker itself."""
import http.server, json, os, time

BASE = os.path.dirname(os.path.abspath(__file__))
STATUS_FILE = "/tmp/clanker-status.json"
PORT = 8765

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=BASE, **kw)
    def do_GET(self):
        if self.path == "/status":
            try:
                with open(STATUS_FILE) as f:
                    body = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(body.encode())
                return
            except Exception:
                self.send_response(404); self.end_headers(); self.wfile.write(b'{}')
                return
        if self.path == "/":
            self.path = "/index.html"
        return super().do_GET()

if __name__ == "__main__":
    print(f"Clanker dashboard on http://localhost:{PORT}")
    http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
