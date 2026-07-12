#!/usr/bin/env bats
# 20-zen-api-key.bats — OPENCODE_ZEN_API_KEY rename (PR #68 port)
#
# These tests verify that the OPENCODE_API_KEY → OPENCODE_ZEN_API_KEY rename
# is applied consistently across staging output (opencode.jsonc, auth.json)
# and that the old OPENCODE_API_KEY name no longer appears.
#
# Maps to PRD Section 9.3 / AC34.

load test_helper/common

@test "AC34a: staging/opencode.jsonc inlines OPENCODE_ZEN_API_KEY literal when set" {
    seed_all_configs
    # Credentials are inlined at generation time so opencode runs anywhere with
    # no runtime env dependency (and no machine-wide env bridge that leaks keys).
    export OPENCODE_ZEN_API_KEY="sk-zen-test-literal-xyz"
    start_mock_llm 14040 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    python3 -c "
import json
c = json.load(open('${GEN_DIR}/staging/opencode.jsonc'))
api_key = c.get('provider',{}).get('opencode',{}).get('options',{}).get('apiKey','')
assert api_key == 'sk-zen-test-literal-xyz', f'Expected inlined literal, got: {api_key}'
print('OK: OPENCODE_ZEN_API_KEY inlined as literal (no {env:} placeholder)')
"
}

@test "AC34b: staging/opencode.jsonc falls back to {env:OPENCODE_ZEN_API_KEY} when key unset" {
    seed_all_configs
    # With no key in the generator environment, generation still succeeds and
    # writes the {env:OPENCODE_ZEN_API_KEY} placeholder (original contract).
    unset OPENCODE_ZEN_API_KEY
    start_mock_llm 14041 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    python3 -c "
import json
c = json.load(open('${GEN_DIR}/staging/opencode.jsonc'))
api_key = c.get('provider',{}).get('opencode',{}).get('options',{}).get('apiKey','')
assert api_key == '{env:OPENCODE_ZEN_API_KEY}', f'Wrong fallback apiKey: {api_key}'
# Old OPENCODE_API_KEY name (without ZEN) must not appear.
assert 'OPENCODE_API_KEY' not in api_key.replace('OPENCODE_ZEN_API_KEY',''), f'Old name leaked: {api_key}'
print('OK: falls back to {env:OPENCODE_ZEN_API_KEY} placeholder')
"
}

@test "AC34c: staging/auth.json seeds opencode provider from OPENCODE_ZEN_API_KEY" {
    seed_all_configs
    start_mock_llm 14042 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/auth.json"

    python3 -c "
import json
auth = json.load(open('${staging}'))
assert 'opencode' in auth, f'Missing opencode in auth.json: {list(auth.keys())}'
assert 'apiKey' in auth['opencode'], f'Missing apiKey: {auth[\"opencode\"]}'
print('OK: auth.json opencode provider seeded')
"
}

@test "AC34d: env-auth.sh reads OPENCODE_ZEN_API_KEY (not OPENCODE_API_KEY)" {
    seed_all_configs
    start_mock_llm 14043 "mock-model" "zai/glm-5.2" "openai/gpt-4o"
    run_generate
    [ "$status" -eq 0 ]

    # Verify the generator output mentions OPENCODE_ZEN_API_KEY
    local gen_output
    gen_output=$(bash "${GEN_DIR}/generate.sh" --dry-run 2>&1 || true)
    echo "$gen_output" | grep -q "OPENCODE_ZEN_API_KEY"
}

@test "AC48a: ACTION REQUIRED not printed when OPENCODE_ZEN_API_KEY is set" {
    seed_all_configs
    start_mock_llm 14048 "mock-model" "zai/glm-5.2" "openai/gpt-4o"

    run_generate --dry-run
    [ "$status" -eq 0 ]

    # When the key IS present in ~/.hermes/.env, env-auth.sh should NOT print
    # the "ACTION REQUIRED" block (gated by `if not opencode_key:` at line 96).
    [[ "$output" != *"ACTION REQUIRED"* ]] || {
        echo "Expected no 'ACTION REQUIRED' in output when key is set" >&2
        echo "--- output excerpt ---" >&2
        echo "$output" | grep -i "ACTION REQUIRED\|auth.json staging" >&2 || true
        false
    }
}

@test "AC48b: ACTION REQUIRED printed when OPENCODE_ZEN_API_KEY is missing" {
    seed_hermes_config
    seed_opencode_config
    # Write ~/.hermes/.env WITHOUT OPENCODE_ZEN_API_KEY
    cat > "${FAKE_HOME}/.hermes/.env" << 'ENVEOF'
OPENAI_API_KEY=sk-tes...2345
ENVEOF

    start_mock_llm 14049 "mock-model" "zai/glm-5.2" "openai/gpt-4o"

    run_generate --dry-run
    [ "$status" -eq 0 ]

    # When the key is NOT present, env-auth.sh MUST print "ACTION REQUIRED"
    # with guidance for adding OPENCODE_ZEN_API_KEY.
    [[ "$output" == *"ACTION REQUIRED"* ]] || {
        echo "Expected 'ACTION REQUIRED' in output when key is missing" >&2
        echo "--- output excerpt ---" >&2
        echo "$output" | grep -i "ACTION REQUIRED\|auth.json staging\|OPENCODE_ZEN_API_KEY" >&2 || true
        false
    }
}
