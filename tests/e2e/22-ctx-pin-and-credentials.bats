#!/usr/bin/env bats
# 22-ctx-pin-and-credentials.bats — Quantized GGUF ctx pin + credential resolution (PR #66 port)
#
# Tests for inherited fixes from reference PR #66:
#   CTX1/CTX2/CTX3 -> quantized GGUF context-length pin
#   CRED1/CRED2/CRED3 -> auth.json OR guard contract
#
# Maps to PRD Section 9.5 / CRED1-2.
# The resolve_ctx_len() tests for CTX1-3 are already covered in 03-config-validity.bats
# (resolve_ctx_len tests at lines 129-178). These tests cover the auth.json contract.

load test_helper/common

# --- CTX pin tests (resolve_ctx_len edge cases from PR #66) -----------------

@test "CTX1: resolve_ctx_len pins quantized qwen3.6 GGUF to 262144" {
    source "${REPO_DIR}/lib/config-hermes.sh"
    result="$(resolve_ctx_len "llama_cpp/qwen3.6-27b-q4_k_m")"
    [ "$result" = "262144" ]
}

@test "CTX2: resolve_ctx_len family wildcard preserved for unquantized qwen3.6" {
    source "${REPO_DIR}/lib/config-hermes.sh"
    result="$(resolve_ctx_len "openai/qwen3.6-32b")"
    [ "$result" = "1048576" ]
}

@test "CTX3: resolve_ctx_len quantized pin does not shadow family wildcard" {
    source "${REPO_DIR}/lib/config-hermes.sh"
    # Both patterns exist; quantized must match first (most-specific-first ordering)
    [ "$(resolve_ctx_len "llama_cpp/qwen3.6-27b-q4_k_s")" = "262144" ]
    [ "$(resolve_ctx_len "llama_cpp/qwen3.6-27b")" = "1048576" ]
}

# --- CTX4: get_limits() pin table (opencode side, parity with reference) -----

@test "CTX4: get_limits pins opencode-go/free-tier families and matches resolve_ctx_len" {
    # get_limits() in config-opencode.sh is the OpenCode-side context/output pin
    # table; it must stay in lockstep with resolve_ctx_len() in config-hermes.sh
    # (two divergent heuristics for the same models). This asserts the load-bearing
    # rows so the table cannot silently narrow again (regression guard for the
    # 200000->262144 drift and the missing kimi/minimax/mimo/nemotron/qwen3.6
    # families). Extracts the get_limits function from the shell script and unit-
    # tests it directly (no live generation needed).
    python3 -c "
import sys
with open('${REPO_DIR}/lib/config-opencode.sh') as f:
    content = f.read()
start = content.index('def get_limits(model_id):')
end = content.index('\n\n', start)
exec('import re\n' + content[start:end])
tests = [
    ('opencode-go/deepseek-v4-pro',     (1000000, 65536)),
    ('opencode/deepseek-v4-flash-free',  (1000000, 65536)),
    ('opencode-go/kimi-k2.6',            (262144, 8192)),
    ('opencode-go/minimax-m3',           (1000000, 8192)),
    ('opencode/mimo-v2.5-free',          (1048576, 8192)),
    ('opencode/nemotron-3-ultra-free',   (131072, 8192)),
    ('opencode/qwen3.6-plus-free',       (1048576, 8192)),
    ('opencode-go/glm-5.2',              (1048576, 131072)),
    ('litellm/o3',                       (262144, 100000)),
    ('anthropic/claude-3.7-sonnet',      (262144, 16384)),
    ('anthropic/claude-3-opus',          (262144, 4096)),
    ('llama_cpp/qwen3.6-27b-q4_k_m',     (262144, 32768)),
    ('llama_cpp/agents-a1-mtp-apex-i-balanced', (262144, 32768)),
    ('llama_cpp/agents-a1-q4_k_m',       (262144, 32768)),
]
for mid, expected in tests:
    result = get_limits(mid)
    assert result == expected, f'FAIL: {mid} -> {result} (expected {expected})'
print(f'OK: {len(tests)}/{len(tests)} get_limits rows pinned')
"
}

# --- CRED tests (auth.json OR guard contract from PR #66) --------------------

@test "CRED1: auth.json seeds litellm from OPENAI_API_KEY in .env" {
    seed_all_configs
    start_mock_llm 14060 "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/auth.json"

    python3 -c "
import json
auth = json.load(open('${staging}'))
assert 'litellm' in auth, f'Missing litellm in auth.json: {list(auth.keys())}'
assert auth['litellm'].get('apiKey') == 'sk-mock-test-key-2345', f'Wrong key: {auth[\"litellm\"]}'
print('OK: auth.json litellm seeded from OPENAI_API_KEY')
"
}

@test "CRED2: auth.json OR guard — litellm seeds from config.yaml fallback when .env has no OPENAI_API_KEY" {
    # Create .env with ONLY OPENCODE_ZEN_API_KEY (no OPENAI_API_KEY)
    # config.yaml still has inline api_key that should be used as fallback
    cat > "${FAKE_HOME}/.hermes/.env" << 'ENVEOF'
OPENCODE_ZEN_API_KEY=sk-zen...-abc
ENVEOF
    seed_hermes_config  # config.yaml has inline api_key: sk-tes...2345
    seed_opencode_config
    start_mock_llm 14061 "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/auth.json"

    python3 -c "
import json
auth = json.load(open('${staging}'))
# OR guard: litellm should still be seeded from config.yaml inline key
assert 'litellm' in auth, f'Missing litellm fallback from config.yaml: {list(auth.keys())}'
assert auth['litellm'].get('apiKey') == 'sk-tes...2345', f'Wrong fallback key: {auth[\"litellm\"]}'
print('OK: auth.json litellm seeded from config.yaml fallback (OR guard)')
"
}

@test "CRED3: auth.json empty when neither provider key available" {
    seed_empty_configs  # no keys in .env or config.yaml
    start_mock_llm 14062 "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    # seed_empty_configs creates minimal config, generate.sh validation will
    # fail on model count/server block — that's expected, we just check auth.json
    run_generate
    # generate.sh may exit non-zero due to validation, but staging files are still created
    # Check auth.json regardless

    local staging="${GEN_DIR}/staging/auth.json"
    assert_file_exists "${staging}"

    python3 -c "
import json
auth = json.load(open('${staging}'))
assert auth == {}, f'Expected empty auth.json when no keys, got: {auth}'
print('OK: auth.json empty when no provider keys available (valid state)')
"
}

@test "CRED4: Hermes overlay key_env fallback on litellm custom_provider when no inline api_key exists" {
    # Create config.yaml without inline api_key
    cat > "${FAKE_HOME}/.hermes/config.yaml" << 'YAML_EOF'
provider: custom:litellm
model:
  name: zai/glm-5.2
  default: zai/glm-5.2
custom_providers:
  - name: litellm
    base_url: http://localhost:4000
YAML_EOF

    # Create .env without OPENAI_API_KEY
    cat > "${FAKE_HOME}/.hermes/.env" << 'ENVEOF'
OPENCODE_ZEN_API_KEY=sk-zen...-abc
ENVEOF

    seed_opencode_config
    start_mock_llm 14063 "zai/glm-5.2" "openai/gpt-4o"
    
    # Ensure OPENAI_API_KEY is not in env of run_generate
    unset OPENAI_API_KEY
    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"
    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
litellm = [cp for cp in c['custom_providers'] if cp.get('name')=='litellm'][0]
assert litellm.get('key_env') == 'OPENAI_API_KEY', litellm
assert 'api_key' not in litellm, 'api_key must be absent on key_env path'
"
}
