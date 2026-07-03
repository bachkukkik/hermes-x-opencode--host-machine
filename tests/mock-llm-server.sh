#!/usr/bin/env bash
# mock-llm-server.sh — lightweight Python-stdlib HTTP server that mimics an
# OpenAI-compatible API.  Used in bats tests so generate.sh can run offline
# without a real LiteLLM proxy.
#
# Usage (source, then call functions):
#   source tests/mock-llm-server.sh
#   start_mock_llm 14001 "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
#   # ... run tests ...
#   stop_mock_llm
#
# Usage (standalone):
#   MOCK_MODELS='["zai/glm-5.2","openai/gpt-4o"]' bash tests/mock-llm-server.sh &
#   curl http://localhost:4000/v1/models
#   kill $!

set -euo pipefail

# ── Globals ──────────────────────────────────────────────────────────────
MOCK_PID=""
MOCK_PORT=""
MOCK_PIDFILE=""

# ── start_mock_llm ───────────────────────────────────────────────────────
# Start a mock LLM HTTP server on the given port, serving the listed models.
#
# Args:
#   $1     — port (default 4000)
#   $2..N  — model ids (default: zai/glm-5.2 openai/gpt-4o anthropic/claude-sonnet-4.6)
#
# Side effects:
#   Exports OPENAI_BASE_URL so generate.sh discovers the mock endpoint.
#   Writes PID to $MOCK_PIDFILE (a mktemp file) for cleanup.
start_mock_llm() {
    local port="${1:-4000}"
    shift || true
    local model_ids=("$@")

    # Default models — 3 well-known families so resolve_ctx_len() pins context_length
    # and generate.sh validation (TC3: context_length count > 1) passes.
    if [ ${#model_ids[@]} -eq 0 ]; then
        model_ids=("zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6")
    fi

    MOCK_PORT="$port"
    export OPENAI_BASE_URL="http://localhost:${port}"

    # Build JSON array of model objects
    local models_json="["
    local first=true
    for mid in "${model_ids[@]}"; do
        if $first; then first=false; else models_json+=", "; fi
        models_json+="{\"id\": \"${mid}\", \"object\": \"model\", \"owned_by\": \"mock\", \"permission\": []}"
    done
    models_json+="]"

    # Kill any previous instance on the same port
    if [ -n "${MOCK_PID:-}" ] && kill -0 "${MOCK_PID}" 2>/dev/null; then
        kill "${MOCK_PID}" 2>/dev/null || true
        wait "${MOCK_PID}" 2>/dev/null || true
    fi

    # Launch Python HTTP server in background
    python3 -c '
import sys, json, time
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(sys.argv[1])
MODELS = json.loads(sys.argv[2])

class MockHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[mock-llm] {args[0]}", file=sys.stderr, flush=True)

    def _send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # -- health ----------------------------------------------------------
    def do_GET(self):
        if self.path == "/health":
            self._send_json(200, {"status": "OK"})
        elif self.path == "/v1/models":
            self._send_json(200, {
                "object": "list",
                "data": MODELS,
            })
        else:
            self._send_json(404, {"error": "not found"})

    # -- chat completions (streaming + non-streaming) -------------------
    def do_POST(self):
        if self.path.startswith("/v1/chat/completions"):
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length else b""
            try:
                body = json.loads(raw) if raw else {}
            except json.JSONDecodeError:
                body = {}

            model = body.get("model", MODELS[0]["id"])
            stream = body.get("stream", False)
            request_id = f"chatcmpl-mock-{int(time.time())}"
            created = int(time.time())

            if stream:
                chunk = {
                    "id": request_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [{
                        "index": 0,
                        "delta": {"role": "assistant", "content": "Mock LLM response"},
                        "finish_reason": None,
                    }],
                }
                final = {
                    "id": request_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [{
                        "index": 0,
                        "delta": {},
                        "finish_reason": "stop",
                    }],
                }
                payload = (
                    f"data: {json.dumps(chunk)}\n\n"
                    f"data: {json.dumps(final)}\n\n"
                    "data: [DONE]\n\n"
                ).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            else:
                self._send_json(200, {
                    "id": request_id,
                    "object": "chat.completion",
                    "created": created,
                    "model": model,
                    "choices": [{
                        "index": 0,
                        "message": {"role": "assistant", "content": "Mock LLM response"},
                        "finish_reason": "stop",
                    }],
                    "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
                })
        else:
            self._send_json(404, {"error": "not found"})

if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", PORT), MockHandler)
    print(f"[mock-llm] listening on 127.0.0.1:{PORT}", file=sys.stderr, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
' "${port}" "${models_json}" &

    MOCK_PID=$!

    # Write PID to a temp file for external cleanup
    MOCK_PIDFILE=$(mktemp /tmp/mock-llm-pid.XXXXXX)
    echo "${MOCK_PID}" > "${MOCK_PIDFILE}"
    export MOCK_PIDFILE

    # Wait for the server to be ready
    local waited=0
    while ! curl -sf --max-time 1 "http://localhost:${port}/health" >/dev/null 2>&1; do
        sleep 0.2
        waited=$((waited + 1))
        if [ "$waited" -gt 25 ]; then
            echo "ERROR: mock LLM server did not start on port ${port}" >&2
            return 1
        fi
    done

    echo "[mock-llm] started on port ${port} (pid ${MOCK_PID}, models: ${model_ids[*]})" >&2
}

# ── stop_mock_llm ────────────────────────────────────────────────────────
# Kill the mock LLM server and clean up the PID file.
stop_mock_llm() {
    if [ -n "${MOCK_PID:-}" ] && kill -0 "${MOCK_PID}" 2>/dev/null; then
        kill "${MOCK_PID}" 2>/dev/null || true
        wait "${MOCK_PID}" 2>/dev/null || true
        echo "[mock-llm] stopped (pid ${MOCK_PID})" >&2
    fi
    MOCK_PID=""
    # Clean up PID file
    if [ -n "${MOCK_PIDFILE:-}" ] && [ -f "${MOCK_PIDFILE}" ]; then
        rm -f "${MOCK_PIDFILE}"
    fi
    MOCK_PIDFILE=""
    unset OPENAI_BASE_URL
}

# ── Standalone mode ──────────────────────────────────────────────────────
# When executed directly (not sourced), start the server and block.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Read models from MOCK_MODELS env var (JSON array) or use defaults
    local_models="${MOCK_MODELS:-}"
    local_port="${MOCK_PORT:-4000}"

    if [ -n "$local_models" ]; then
        # Parse JSON array into bash args
        mapfile -t parsed < <(python3 -c "import sys,json; print('\n'.join(m['id'] for m in json.loads(sys.argv[1])))" "$local_models")
        start_mock_llm "$local_port" "${parsed[@]}"
    else
        start_mock_llm "$local_port"
    fi

    # Block until interrupted
    trap 'stop_mock_llm; exit 0' INT TERM
    wait "${MOCK_PID}"
fi
