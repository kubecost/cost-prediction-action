#!/usr/bin/env python3
"""
kubecost-v3-proxy.py
====================
Thin reverse proxy that makes the Kubecost cost-prediction-action image
(built against Kubecost v2 / OpenCost endpoints) work with a Kubecost v3
backend.

Translation performed (only when UPSTREAM answers 404, i.e. Kubecost v3;
Kubecost v2 responses pass through unchanged)
---------------------
  GET  <prefix>/clusterInfo
       → GET  {UPSTREAM}<prefix>/clusterInfoMap
         Takes the first cluster entry from .data (the lowest cluster ID; the
         server sorts its keys) and returns it in the v2 shape the image reads.
  GET  <prefix>/getConfigs
       → {"data": {"currencyCode": "USD"}} (v3 has no currency endpoint)

All other requests are forwarded to UPSTREAM unchanged (transparent proxy).
action-enhanced/predict.sh runs this in front of the image when
kubecost_api_path is set.

Usage
-----
  export KUBECOST_UPSTREAM=https://demo.kubecost.io
  python3 kubecost-v3-proxy.py          # listens on 127.0.0.1:19090

Then point the action at:
  kubecost_api_path: http://localhost:19090/model

Environment variables
---------------------
  KUBECOST_UPSTREAM   Base URL of the real Kubecost v3 instance (no trailing slash)
                      Default: https://demo.kubecost.io
  PROXY_PORT          Port to listen on. Default: 19090
  PROXY_HOST          Interface to bind to. Default: 127.0.0.1
"""

import http.server
import json
import os
import sys
import urllib.error
import urllib.request

UPSTREAM = os.environ.get("KUBECOST_UPSTREAM", "https://demo.kubecost.io").rstrip("/")
PORT     = int(os.environ.get("PROXY_PORT", "19090"))
HOST     = os.environ.get("PROXY_HOST", "127.0.0.1")


def fetch(method, url, body=None, headers=None):
    """Make an upstream HTTP request, return (status, headers, body_bytes)."""
    req = urllib.request.Request(url, data=body, method=method)
    if headers:
        for k, v in headers.items():
            # Don't forward hop-by-hop headers
            if k.lower() not in ("host", "connection", "transfer-encoding"):
                req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def translate_cluster_info(url):
    """
    Call clusterInfoMap (url) on the upstream and return a v2-compatible
    /clusterInfo response body (bytes) and the HTTP status code.

    v3 clusterInfoMap response:
      {"code": 200, "data": {"<clusterID>": {"id": "...", "name": "...", ...}}}

    v2 clusterInfo response the image expects:
      {"data": {"id": "...", "name": "...", ...}}
    """
    status, _, body = fetch("GET", url)

    if status != 200:
        return status, body  # pass the error through as-is

    try:
        payload = json.loads(body)
        clusters = payload.get("data", {})
        if not clusters:
            return 404, b'{"error": "no clusters found in clusterInfoMap"}'
        # Take the first cluster entry and wrap in {"data": {...}} — the shape
        # the image's clusterInfoResponse struct expects (json:"data" envelope).
        first = next(iter(clusters.values()))
        return 200, json.dumps({"data": first}).encode()
    except Exception as exc:
        return 502, json.dumps({"error": f"proxy failed to parse clusterInfoMap: {exc}"}).encode()


class ProxyHandler(http.server.BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        print(f"[proxy] {self.address_string()} {fmt % args}", file=sys.stderr, flush=True)

    def _reply(self, status, headers, body):
        self.send_response(status)
        for k, v in headers.items():
            if k.lower() not in ("connection", "transfer-encoding", "content-length"):
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _forward(self, method):
        path = self.path  # includes query string
        route = path.split("?", 1)[0].rstrip("/")

        # ── Kubecost v3 translations (only when the upstream answers 404) ──
        if method == "GET" and route.endswith(("/clusterInfo", "/getConfigs")):
            status, headers, body = fetch("GET", f"{UPSTREAM}{path}")
            if status == 404 and route.endswith("/clusterInfo"):
                map_url = f"{UPSTREAM}{route[:-len('/clusterInfo')]}/clusterInfoMap"
                print(f"[proxy] TRANSLATE GET {route} -> clusterInfoMap", file=sys.stderr, flush=True)
                status, body = translate_cluster_info(map_url)
                headers = {"Content-Type": "application/json", "X-Proxy-Translated": "clusterInfo-to-clusterInfoMap"}
            elif status == 404:
                # The image uses getConfigs only for the currency label.
                print(f"[proxy] TRANSLATE GET {route} -> getConfigs stub (USD)", file=sys.stderr, flush=True)
                status, body = 200, json.dumps({"data": {"currencyCode": "USD"}}).encode()
                headers = {"Content-Type": "application/json"}
            self._reply(status, headers, body)
            return

        # ── Transparent proxy for everything else ─────────────────────────────
        url = f"{UPSTREAM}{path}"

        # Read request body if present
        body = None
        length = int(self.headers.get("Content-Length", 0))
        if length:
            body = self.rfile.read(length)

        # Forward relevant headers
        fwd_headers = {
            k: v for k, v in self.headers.items()
            if k.lower() not in ("host", "connection", "transfer-encoding", "content-length")
        }

        status, resp_headers, resp_body = fetch(method, url, body=body, headers=fwd_headers)
        self._reply(status, resp_headers, resp_body)

    def do_GET(self):    self._forward("GET")
    def do_POST(self):   self._forward("POST")
    def do_PUT(self):    self._forward("PUT")
    def do_DELETE(self): self._forward("DELETE")
    def do_HEAD(self):   self._forward("HEAD")


if __name__ == "__main__":
    server = http.server.HTTPServer((HOST, PORT), ProxyHandler)
    print(f"[proxy] Kubecost v3 compatibility proxy", file=sys.stderr)
    print(f"[proxy] Upstream : {UPSTREAM}", file=sys.stderr)
    print(f"[proxy] Listening: http://{HOST}:{PORT}", file=sys.stderr)
    print(f"[proxy] Set kubecost_api_path: http://{HOST}:{PORT}/model", file=sys.stderr)
    print(f"[proxy] Press Ctrl+C to stop", file=sys.stderr, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[proxy] Stopped.", file=sys.stderr)
