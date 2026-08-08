#!/usr/bin/env python3
"""Minimal, fail-closed OpenAI Responses policy gateway for Open WebUI."""

import http.server
import json
import os
import ssl
import urllib.error
import urllib.request


UPSTREAM = "https://api.openai.com/v1"
API_KEY_FILE = os.environ["OPENAI_API_KEY_FILE"]
LISTEN_HOST = os.environ.get("LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8084"))

MODELS = {
    "economy": {
        "name": "Economy — 1×",
        "upstream": "gpt-5.6-luna",
        "reasoning": "low",
        "max_output_tokens": 4096,
        "description": (
            "Efficient, repeatable everyday work. $0.20 short-context input / "
            "$1.20 output per 1M tokens; 1×; about $0.002 normally or $0.013 "
            "with one search. "
            "Hosted search: $0.01 per call, up to three calls."
        ),
    },
    "everyday": {
        "name": "Everyday — 10×",
        "upstream": "gpt-5.6-terra",
        "reasoning": "medium",
        "max_output_tokens": 8192,
        "description": (
            "Balanced intelligence and cost. $2 short-context input / $12 output "
            "per 1M tokens; 10×; about $0.016 normally or $0.036 with one search. "
            "Hosted search: $0.01 per call, up to three calls."
        ),
    },
    "high-quality": {
        "name": "High Quality — 25×",
        "upstream": "gpt-5.6-sol",
        "reasoning": "medium",
        "max_output_tokens": 8192,
        "description": (
            "Frontier capability for difficult analysis and polished results. "
            "$5 short-context input / $30 output per 1M tokens; 25×; about $0.040 "
            "normally or $0.075 with one search. Hosted search: $0.01 per call, "
            "up to three calls."
        ),
    },
}

RESEARCH_POLICY = """
Use hosted web search when the request asks for current or changing facts,
citations, comparisons, verification, or source-backed research. Prefer primary
sources. Put citations immediately after the claims they support and clearly
separate sourced facts from inference. Do not search for timeless writing,
summarization, translation, or transformation tasks. Honor an explicit request
not to search. If search fails, report the failure instead of presenting an
ungrounded answer as researched. Reasoning tokens and retrieved web content are
billed. Never invoke more than three hosted-search calls.
""".strip()


def api_key():
    with open(API_KEY_FILE, encoding="utf-8") as key_file:
        return key_file.read().strip()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("openai-policy-gateway:", fmt % args, flush=True)

    def send_json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {"status": "ok"})
            return
        if self.path.rstrip("/") == "/v1/models":
            self.send_json(
                200,
                {
                    "object": "list",
                    "data": [
                        {
                            "id": model_id,
                            "name": policy["name"],
                            "object": "model",
                            "owned_by": "homelab",
                            "description": policy["description"],
                        }
                        for model_id, policy in MODELS.items()
                    ],
                },
            )
            return
        self.send_json(404, {"error": {"message": "Not found"}})

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/responses":
            self.send_json(
                400,
                {"error": {"message": "Only the stateless Responses API is enabled"}},
            )
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length))
            policy = MODELS[payload.get("model")]
        except (ValueError, json.JSONDecodeError, KeyError):
            self.send_json(400, {"error": {"message": "Unknown or invalid curated model"}})
            return

        # Discard every caller-controlled provider option and rebuild the
        # allowlisted request. Open WebUI remains the conversation state owner.
        allowed = {
            key: payload[key]
            for key in ("input", "stream")
            if key in payload
        }
        allowed.update(
            {
                "model": policy["upstream"],
                "store": False,
                "reasoning": {"effort": policy["reasoning"]},
                "max_output_tokens": policy["max_output_tokens"],
                "max_tool_calls": 3,
                "tools": [
                    {
                        "type": "web_search",
                        "search_context_size": "medium",
                    }
                ],
                "instructions": "\n\n".join(
                    part
                    for part in (payload.get("instructions", "").strip(), RESEARCH_POLICY)
                    if part
                ),
            }
        )

        request = urllib.request.Request(
            f"{UPSTREAM}/responses",
            data=json.dumps(allowed).encode(),
            headers={
                "Authorization": f"Bearer {api_key()}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            response = urllib.request.urlopen(
                request,
                timeout=300,
                context=ssl.create_default_context(),
            )
        except urllib.error.HTTPError as error:
            error_body = error.read()
            self.send_response(error.code)
            self.send_header("Content-Type", error.headers.get_content_type())
            self.send_header("Content-Length", str(len(error_body)))
            self.end_headers()
            self.wfile.write(error_body)
            return
        except (urllib.error.URLError, TimeoutError) as error:
            self.send_json(
                502,
                {"error": {"message": f"Hosted Responses API unavailable: {error.reason}"}},
            )
            return

        self.send_response(response.status)
        content_type = response.headers.get("Content-Type", "application/json")
        self.send_header("Content-Type", content_type)
        if content_type.startswith("text/event-stream"):
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            while chunk := response.read(16384):
                self.wfile.write(chunk)
                self.wfile.flush()
            self.close_connection = True
        else:
            body = response.read()
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)


if __name__ == "__main__":
    http.server.ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler).serve_forever()
