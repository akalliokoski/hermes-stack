#!/usr/bin/env python3
import http.client
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_HOST = os.environ.get("HERMES_DASHBOARD_PROXY_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("HERMES_DASHBOARD_PROXY_PORT", "9120"))
UPSTREAM_HOST = os.environ.get("HERMES_DASHBOARD_UPSTREAM_HOST", "127.0.0.1")
UPSTREAM_PORT = int(os.environ.get("HERMES_DASHBOARD_UPSTREAM_PORT", "9119"))
UPSTREAM_HOST_HEADER = os.environ.get("HERMES_DASHBOARD_UPSTREAM_HOST_HEADER", f"{UPSTREAM_HOST}:{UPSTREAM_PORT}")

HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
}


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _forward(self):
        body = None
        if "Content-Length" in self.headers:
            body = self.rfile.read(int(self.headers["Content-Length"]))

        upstream_headers = {}
        for key, value in self.headers.items():
            if key.lower() in HOP_BY_HOP_HEADERS:
                continue
            upstream_headers[key] = value
        upstream_headers["Host"] = UPSTREAM_HOST_HEADER
        upstream_headers["X-Forwarded-Host"] = self.headers.get("Host", "")
        upstream_headers["X-Forwarded-Proto"] = "https" if self.headers.get("X-Forwarded-Proto") == "https" else "http"
        upstream_headers["X-Forwarded-For"] = self.client_address[0]
        upstream_headers["X-Real-IP"] = self.client_address[0]

        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=30)
        try:
            conn.request(self.command, self.path, body=body, headers=upstream_headers)
            resp = conn.getresponse()
            resp_body = resp.read()

            self.send_response(resp.status, resp.reason)
            for key, value in resp.getheaders():
                if key.lower() in HOP_BY_HOP_HEADERS:
                    continue
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(resp_body)))
            self.end_headers()
            if resp_body:
                self.wfile.write(resp_body)
        finally:
            conn.close()

    def do_GET(self):
        self._forward()

    def do_POST(self):
        self._forward()

    def do_PUT(self):
        self._forward()

    def do_PATCH(self):
        self._forward()

    def do_DELETE(self):
        self._forward()

    def do_OPTIONS(self):
        self._forward()

    def do_HEAD(self):
        self._forward()

    def log_message(self, format, *args):
        return


if __name__ == "__main__":
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), ProxyHandler)
    server.serve_forever()
