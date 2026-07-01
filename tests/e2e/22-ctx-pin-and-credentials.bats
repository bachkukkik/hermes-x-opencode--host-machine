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
