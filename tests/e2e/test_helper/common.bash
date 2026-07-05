#!/usr/bin/env bash
# tests/e2e/test_helper/common.bash — shared setup/teardown for host-generator bats tests.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")/.." && pwd)"
export REPO_DIR

setup() {
    TEST_TMP="$(mktemp -d /tmp/host-gen-test.XXXXXX)"
    export TEST_TMP
    FAKE_HOME="${TEST_TMP}/home"
    mkdir -p "${FAKE_HOME}/.hermes" \
             "${FAKE_HOME}/.config/opencode" \
             "${FAKE_HOME}/.local/share/opencode"
    export HOME="${FAKE_HOME}"
    GEN_DIR="${FAKE_HOME}/.hermes/host-config-gen"
    export GEN_DIR
    mkdir -p "${GEN_DIR}/lib"
    # Clean environment — prevent repo .env from leaking test defaults
    unset HERMES_YOLO_MODE HERMES_DELEGATION_MODEL HERMES_DELEGATION_PROVIDER
    unset HERMES_GOAL_MAX_TURNS HERMES_COMPRESSION_THRESHOLD
    unset OPENAI_DEFAULT_MODEL OPENCODE_DEFAULT_MODEL OPENCODE_SMALL_MODEL OPENCODE_FALLBACK_MODEL
    unset HERMES_DELEGATION_MAX_ITERATIONS
    cp "${REPO_DIR}/generate.sh" "${GEN_DIR}/"
    cp "${REPO_DIR}/lib/"*.sh     "${GEN_DIR}/lib/"
    chmod +x "${GEN_DIR}/generate.sh"
}

teardown() {
    stop_mock_llm 2>/dev/null || true
    rm -rf "${TEST_TMP:-/tmp/NONEXISTENT}" 2>/dev/null || true
}

MOCK_PID=""
MOCK_PORT=""

start_mock_llm() {
    local port="${1:-14000}"
    shift || true
    local model_ids=("$@")
    if [ ${#model_ids[@]} -eq 0 ]; then
        model_ids=("mock-model" "zai/glm-5.2" "openai/gpt-4o")
    fi
    MOCK_PORT="$port"
    export OPENAI_BASE_URL="http://localhost:${port}"
    export OPENAI_API_KEY="sk-mock-test-key"
    local models_json="["
    local first=true
    for mid in "${model_ids[@]}"; do
        if $first; then first=false; else models_json+=", "; fi
        models_json+="{\"id\": \"${mid}\", \"object\": \"model\", \"owned_by\": \"mock\"}"
    done
    models_json+="]"
    python3 -c "
import sys, json
from http.server import HTTPServer, BaseHTTPRequestHandler
port = int(sys.argv[1])
models_data = json.loads(sys.argv[2])
class H(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def _j(self,c,o):
        b=json.dumps(o).encode()
        self.send_response(c)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(b)))
        self.end_headers()
        self.wfile.write(b)
    def do_GET(self):
        if self.path=='/health': self._j(200,{'status':'OK'})
        elif self.path=='/v1/models': self._j(200,{'object':'list','data':models_data})
        else: self._j(404,{'error':'not found'})
HTTPServer(('127.0.0.1',port),H).serve_forever()
" "${port}" "${models_json}" &
    MOCK_PID=$!
    local waited=0
    while ! curl -sf --max-time 1 "http://localhost:${port}/health" >/dev/null 2>&1; do
        sleep 0.2
        waited=$((waited + 1))
        if [ "$waited" -gt 25 ]; then
            echo "ERROR: mock LiteLLM server did not start" >&2
            return 1
        fi
    done
}

stop_mock_llm() {
    if [ -n "${MOCK_PID:-}" ]; then
        kill "${MOCK_PID}" 2>/dev/null || true
        wait "${MOCK_PID}" 2>/dev/null || true
        MOCK_PID=""
    fi
    unset OPENAI_BASE_URL
}

seed_hermes_config() {
    cat > "${FAKE_HOME}/.hermes/config.yaml" << 'YEOF'
model:
  api_key: "sk-tes...2345"
  default: "zai/glm-5.2"
  name: "zai/glm-5.2"
custom_providers:
  - name: litellm
    base_url: "http://localhost:4000"
    api_key: "sk-tes...2345"
    model: "zai/glm-5.2"
YEOF
}

seed_opencode_config() {
    cat > "${FAKE_HOME}/.config/opencode/opencode.jsonc" << 'JEOF'
{
  "model": "opencode/deepseek-v4-flash-free",
  "small_model": "opencode/deepseek-v4-flash-free",
  "permission": {
    "bash": {
      "deny": ["rm -rf /", "sudo", "chmod 777 /"]
    }
  },
  "plugin": ["cc-safety-net", "opencode-copilot"],
  "agent": {
    "build": {
      "mode": "interactive",
      "description": "Build agent for coding tasks",
      "model": "opencode/deepseek-v4-flash-free"
    },
    "plan": {
      "mode": "interactive",
      "description": "Planning agent for strategy",
      "model": "opencode/deepseek-v4-flash-free"
    }
  },
  "experimental": {"enable_codex": true},
  "server": {"port": 4096},
  "provider": {
    "opencode": {
      "options": {"apiKey": "{env:OPENCODE_ZEN_API_KEY}"}
    },
    "litellm": {
      "options": {"apiKey": "{env:OPENAI_API_KEY}", "baseURL": "http://localhost:4000"},
      "models": {
        "zai/glm-5.2": {
          "name": "zai/glm-5.2",
          "limit": {"context": 1048576, "output": 131072}
        }
      }
    }
  }
}
JEOF
}

seed_env_file() {
    cat > "${FAKE_HOME}/.hermes/.env" << 'ENVEOF'
OPENCODE_ZEN_API_KEY=sk-zen...-abc
OPENAI_API_KEY=sk-mock-test-key-2345
ENVEOF
}

# seed_all_configs — convenience
seed_all_configs() {
    seed_hermes_config
    seed_opencode_config
    seed_env_file
}

seed_empty_configs() {
    cat > "${FAKE_HOME}/.hermes/config.yaml" << 'YEOF'
model:
  default: "zai/glm-5.2"
YEOF
    cat > "${FAKE_HOME}/.config/opencode/opencode.jsonc" << 'JEOF'
{}
JEOF
    echo "" > "${FAKE_HOME}/.hermes/.env"
}

assert_file_contains() {
    local file="$1" pattern="$2"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        echo "Expected file '$file' to contain: $pattern" >&2
        head -50 "$file" >&2
        return 1
    fi
}

assert_file_not_contains() {
    local file="$1" pattern="$2"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "Expected file '$file' NOT to contain: $pattern" >&2
        return 1
    fi
}

assert_json_valid() {
    python3 -m json.tool "$1" >/dev/null 2>&1 || {
        echo "Expected '$1' to be valid JSON" >&2
        return 1
    }
}

assert_yaml_valid() {
    python3 -c "import yaml; yaml.safe_load(open('$1'))" 2>/dev/null || {
        echo "Expected '$1' to be valid YAML" >&2
        return 1
    }
}

assert_file_exists() {
    if [ ! -f "$1" ]; then
        echo "Expected file '$1' to exist" >&2
        return 1
    fi
}

assert_file_not_exists() {
    if [ -f "$1" ]; then
        echo "Expected file '$1' NOT to exist" >&2
        return 1
    fi
}

assert_success() {
    if ! "$@"; then
        echo "Expected command to succeed: $*" >&2
        return 1
    fi
}

run_generate() {
    run bash "${GEN_DIR}/generate.sh" "$@"
}
