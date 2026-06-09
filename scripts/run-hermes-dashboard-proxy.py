#!/usr/bin/env python3
"""Host-header rewriting proxy for the localhost-bound Hermes dashboard.

The dashboard is intentionally bound to 127.0.0.1 so it does not listen on a
public interface. Tailscale Serve publishes this proxy on a tailnet-only HTTPS
port. The proxy forwards requests to the dashboard while forcing the upstream
Host header back to 127.0.0.1:9119, which satisfies Hermes' DNS-rebinding guard.

Hermes Desktop also needs the dashboard WebSocket at /api/ws. The original
HTTP-only proxy made /api/status work while chat failed with "Could not connect
to Hermes gateway". This implementation handles WebSocket upgrade requests by
opening a raw TCP connection to the dashboard, forwarding the upgrade request,
and then tunneling bytes in both directions.
"""

from __future__ import annotations

import http.client
import os
import selectors
import socket
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import cast

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


def _header_is_upgrade(value: str | None) -> bool:
    if not value:
        return False
    return any(part.strip().lower() == "upgrade" for part in value.split(","))


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _upstream_headers(self, *, include_hop_by_hop: bool = False) -> dict[str, str]:
        upstream_headers: dict[str, str] = {}
        for key, value in self.headers.items():
            if not include_hop_by_hop and key.lower() in HOP_BY_HOP_HEADERS:
                continue
            if key.lower() == "host":
                continue
            upstream_headers[key] = value
        upstream_headers["Host"] = UPSTREAM_HOST_HEADER
        upstream_headers["X-Forwarded-Host"] = self.headers.get("Host", "")
        upstream_headers["X-Forwarded-Proto"] = "https" if self.headers.get("X-Forwarded-Proto") == "https" else "http"
        upstream_headers["X-Forwarded-For"] = self.client_address[0]
        upstream_headers["X-Real-IP"] = self.client_address[0]
        return upstream_headers

    def _forward_http(self):
        body = None
        if "Content-Length" in self.headers:
            body = self.rfile.read(int(self.headers["Content-Length"]))

        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=30)
        try:
            conn.request(self.command, self.path, body=body, headers=self._upstream_headers())
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

    def _forward_websocket(self):
        upstream = socket.create_connection((UPSTREAM_HOST, UPSTREAM_PORT), timeout=30)
        upstream.settimeout(None)
        try:
            request_lines = [f"{self.command} {self.path} HTTP/1.1\r\n"]
            headers = self._upstream_headers(include_hop_by_hop=True)
            # Preserve the browser/client WebSocket upgrade headers exactly.
            headers["Connection"] = self.headers.get("Connection", "Upgrade")
            headers["Upgrade"] = self.headers.get("Upgrade", "websocket")
            origin = headers.get("Origin") or headers.get("origin")
            if origin:
                parsed_origin = urllib.parse.urlparse(origin)
                if parsed_origin.scheme in {"http", "https"}:
                    # The upstream dashboard is loopback-bound and validates
                    # WebSocket Origin against its bound Host to defend against
                    # DNS rebinding. Remote tailnet browsers/Desktop reach this
                    # host-native proxy with a non-loopback Origin, so present
                    # the upstream leg as a same-origin loopback connection.
                    headers.pop("origin", None)
                    headers["Origin"] = f"http://{UPSTREAM_HOST_HEADER}"
            for key, value in headers.items():
                request_lines.append(f"{key}: {value}\r\n")
            request_lines.append("\r\n")
            upstream.sendall("".join(request_lines).encode("utf-8"))

            selector = selectors.DefaultSelector()
            selector.register(self.connection, selectors.EVENT_READ, upstream)
            selector.register(upstream, selectors.EVENT_READ, self.connection)
            while True:
                events = selector.select(timeout=60)
                if not events:
                    break
                for key, _mask in events:
                    src = cast(socket.socket, key.fileobj)
                    dst = cast(socket.socket, key.data)
                    data = src.recv(65536)
                    if not data:
                        return
                    dst.sendall(data)
        finally:
            try:
                upstream.close()
            except OSError:
                pass

    def _forward(self):
        if self.command == "GET" and _header_is_upgrade(self.headers.get("Connection")) and self.headers.get("Upgrade", "").lower() == "websocket":
            self._forward_websocket()
        else:
            self._forward_http()

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
