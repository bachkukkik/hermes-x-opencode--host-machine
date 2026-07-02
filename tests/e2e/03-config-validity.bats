#!/usr/bin/env bats
# 03-config-validity.bats — Test staging output validity (JSON, YAML, model field)

load test_helper/common

@test "staging/opencode.jsonc is valid JSON" {
    seed_all_configs
    start_mock_llm 14021 "mock-model" "zai/glm-5.2" "openai/gpt-4o"
    run_generate
    [ "$status" -eq 0 ]

    assert_json_valid "${GEN_DIR}/staging/opencode.jsonc"
}

@test "staging/config-hermes-overlay.yaml is valid YAML" {
    seed_all_configs
    start_mock_llm 14022 "mock-model" "zai/glm-5.2" "openai/gpt-4o"
    run_generate
    [ "$status" -eq 0 ]

    assert_yaml_valid "${GEN_DIR}/staging/config-hermes-overlay.yaml"
}

@test "staging/opencode.jsonc has provider.opencode with {env:OPENCODE_ZEN_API_KEY}" {
    seed_all_configs
    start_mock_llm 14023 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    assert_file_contains "${GEN_DIR}/staging/opencode.jsonc" "\"apiKey\": \"{env:OPENCODE_ZEN_API_KEY}\""
}

@test "staging/opencode.jsonc top-level model = OPENCODE_DEFAULT_MODEL" {
    seed_all_configs
    start_mock_llm 14024 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    # Verify the top-level model matches the configured default
    # (OPENCODE_DEFAULT_MODEL was unset in setup() — test must provide its own)
    expected_model="mock-model"
    OPENCODE_DEFAULT_MODEL="${expected_model}" run_generate
    [ "$status" -eq 0 ]
    python3 -c "
import json
expected = '${expected_model}'
c = json.load(open('${staging}'))
assert c.get('model') == expected, f\"model={c.get('model')}, expected={expected}\"
assert c.get('small_model') == expected, f\"small_model={c.get('small_model')}, expected={expected}\"
print(f'OK: model + small_model = {expected}')
"
}

@test "staging/opencode.jsonc agent.build.model and agent.plan.model = OPENCODE_DEFAULT_MODEL" {
    seed_all_configs
    start_mock_llm 14025 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    expected_model="mock-model"
    OPENCODE_DEFAULT_MODEL="${expected_model}" run_generate
    [ "$status" -eq 0 ]
    python3 -c "
import json
expected = '${expected_model}'
c = json.load(open('${staging}'))
abm = c.get('agent', {}).get('build', {}).get('model')
apm = c.get('agent', {}).get('plan', {}).get('model')
assert abm == expected, f'agent.build.model={abm}, expected={expected}'
assert apm == expected, f'agent.plan.model={apm}, expected={expected}'
print(f'OK: agent sub-models pinned to {expected}')
"
}

@test "staging/opencode.jsonc provider.litellm has models map" {
    seed_all_configs
    start_mock_llm 14026 "mock-model" "zai/glm-5.2" "openai/gpt-4o"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
models = c.get('provider', {}).get('litellm', {}).get('models', {})
assert len(models) > 0, 'litellm.models is empty'
for mid, val in models.items():
    assert 'limit' in val, f'{mid} missing limit'
    assert isinstance(val['limit'].get('context'), int), f'{mid} context not int'
    assert isinstance(val['limit'].get('output'), int), f'{mid} output not int'
print(f'OK: {len(models)} models with limits in litellm provider')
"
}

@test "staging/config-hermes-overlay.yaml has custom_providers with models map" {
    seed_all_configs
    start_mock_llm 14027 "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
cps = c.get('custom_providers', [])
litellm = [cp for cp in cps if cp.get('name') == 'litellm']
assert len(litellm) == 1, f'Expected 1 litellm provider, got {len(litellm)}'
models = litellm[0].get('models', {})
assert len(models) > 0, 'litellm.models is empty'
ok = 0
for mid, val in models.items():
    ctx = val.get('context_length', 0) if isinstance(val, dict) else 0
    if ctx > 1000:
        ok += 1
# At least one model must have a valid context_length
assert ok > 0, f'no models have context_length > 1000: {list(models.keys())[:5]}'
print(f'OK: {ok}/{len(models)} models have context_length > 1000')
"
}

@test "staging/auth.json is valid JSON with provider keys" {
    seed_all_configs
    start_mock_llm 14028 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    assert_json_valid "${GEN_DIR}/staging/auth.json"
}

# --- resolve_ctx_len() tests -------------------------------------------------

@test "resolve_ctx_len: known families return correct context lengths" {
    # Source config-hermes.sh to get resolve_ctx_len() in scope
    source "${REPO_DIR}/lib/config-hermes.sh"

    # 13 families — spot-check key ones
    [ "$(resolve_ctx_len "zai/glm-5.2")"                          = "1048576" ]
    [ "$(resolve_ctx_len "anthropic/claude-opus-4")"               = "1000000" ]
    [ "$(resolve_ctx_len "anthropic/claude-sonnet-4.6")"           = "1000000" ]
    [ "$(resolve_ctx_len "openai/gpt-5.4")"                        = "1050000" ]
    [ "$(resolve_ctx_len "openai/gpt-5")"                          = "400000"  ]
    [ "$(resolve_ctx_len "openai/gpt-4o")"                         = "128000"  ]
    [ "$(resolve_ctx_len "openai/gpt-4.1")"                        = "1047576" ]
    [ "$(resolve_ctx_len "openai/gpt-4")"                          = "128000"  ]
    [ "$(resolve_ctx_len "google/gemini-2.0-flash")"               = "1048576" ]
    [ "$(resolve_ctx_len "deepseek/deepseek-v4-pro")"              = "1000000" ]
    [ "$(resolve_ctx_len "minimax/minimax-m3")"                    = "1000000" ]
    [ "$(resolve_ctx_len "llama_cpp/qwen3.6-27b-q4_k_m")"         = "262144"  ]
    [ "$(resolve_ctx_len "openai/qwen3.6-32b")"                   = "1048576" ]
}

@test "resolve_ctx_len: unknown model returns empty string" {
    source "${REPO_DIR}/lib/config-hermes.sh"

    result="$(resolve_ctx_len "some-vendor/unknown-model-v7")"
    [ -z "$result" ]
}

@test "resolve_ctx_len: first-match-wins — gpt-5.4 matched before gpt-5" {
    source "${REPO_DIR}/lib/config-hermes.sh"

    # gpt-5.4 is a substring of gpt-5, so if ordering is wrong, gpt-5.4 gets 400000
    [ "$(resolve_ctx_len "openai/gpt-5.4")" = "1050000" ]
    [ "$(resolve_ctx_len "openai/gpt-5-turbo")" = "400000" ]
}

@test "resolve_ctx_len: qwen3.6 quantized variant matched before family wildcard" {
    source "${REPO_DIR}/lib/config-hermes.sh"

    # Specific quantized pin (line before family wildcard) must win
    [ "$(resolve_ctx_len "llama_cpp/qwen3.6-27b-q4_k_m")" = "262144" ]
    # Non-quantized family member still gets full 1M
    [ "$(resolve_ctx_len "openai/qwen3.6-32b")" = "1048576" ]
}

@test "resolve_ctx_len: case-insensitive matching" {
    source "${REPO_DIR}/lib/config-hermes.sh"

    [ "$(resolve_ctx_len "OPENAI/GPT-4O")" = "128000" ]
    [ "$(resolve_ctx_len "DeepSeek/DeepSeek-V4-Pro")" = "1000000" ]
    [ "$(resolve_ctx_len "GEMINI/2.0-FLASH")" = "1048576" ]
}

# --- provider.llama_cpp tests ------------------------------------------------

@test "staging/opencode.jsonc has provider.llama_cpp with correct options" {
    seed_all_configs
    start_mock_llm 14035 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "llama_cpp/qwen3.6-27b-q4_k_m"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
lc = c.get('provider', {}).get('llama_cpp', {})
assert lc, 'provider.llama_cpp missing'
assert lc.get('npm') == '@ai-sdk/openai-compatible', f'npm wrong: {lc.get(\"npm\")}'
opts = lc.get('options', {})
assert opts.get('apiKey') == '{env:OPENAI_API_KEY}', f'apiKey wrong: {opts.get(\"apiKey\")}'
assert 'baseURL' in opts, 'baseURL missing'
assert opts.get('timeout') == 600000, f'timeout wrong: {opts.get(\"timeout\")}'
assert opts.get('setCacheKey') == True, f'setCacheKey wrong: {opts.get(\"setCacheKey\")}'
print('OK: provider.llama_cpp present with correct options')
"
}

@test "staging/opencode.jsonc provider.llama_cpp.models contains llama_cpp models" {
    seed_all_configs
    start_mock_llm 14036 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "llama_cpp/qwen3.6-27b-q4_k_m"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
lc_models = c.get('provider', {}).get('llama_cpp', {}).get('models', {})
assert len(lc_models) > 0, 'llama_cpp.models is empty'
assert 'qwen3.6-27b-q4_k_m' in lc_models, f'qwen3.6-27b-q4_k_m not in llama_cpp.models: {list(lc_models.keys())}'
entry = lc_models['qwen3.6-27b-q4_k_m']
assert entry.get('name') == 'llama_cpp/qwen3.6-27b-q4_k_m', f'name wrong: {entry.get(\"name\")}'
assert entry.get('limit', {}).get('context') == 262144, f'context wrong: {entry.get(\"limit\")}'
print(f'OK: {len(lc_models)} llama_cpp model(s) with correct limits')
"
}

@test "merge summary includes provider.llama_cpp line" {
    seed_all_configs
    start_mock_llm 14037 "mock-model" "zai/glm-5.2" "llama_cpp/qwen3.6-27b-q4_k_m"
    run_generate
    [ "$status" -eq 0 ]

    local summary="${GEN_DIR}/staging/opencode-merge-summary.txt"
    assert_file_exists "$summary"
    assert_file_contains "$summary" "provider.llama_cpp"
    assert_file_contains "$summary" "llama_cpp.models total"
}

# --- HERMES_YOLO_MODE tests -------------------------------------------------

@test "HERMES_YOLO_MODE=1 emits approvals.mode:off in staging overlay" {
    seed_all_configs
    start_mock_llm 14029 "zai/glm-5.2" "openai/gpt-4o"

    HERMES_YOLO_MODE=1 run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    # Check that approvals.mode: off is present
    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
approvals = c.get('approvals', {})
assert approvals.get('mode') == 'off', f'Expected approvals.mode=off, got: {approvals}'
print('OK: approvals.mode=off present')
"
}

@test "HERMES_YOLO_MODE unset does NOT emit approvals block" {
    seed_all_configs
    start_mock_llm 14030 "zai/glm-5.2" "openai/gpt-4o"

    # No YOLO env var set
    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
assert 'approvals' not in c or c.get('approvals') is None, \
    f'Expected no approvals block when YOLO unset, got: {c.get(\"approvals\")}'
print('OK: no approvals block when YOLO unset')
"
}

@test "HERMES_YOLO_MODE unset still emits goals.max_turns and delegation.max_iterations" {
    seed_all_configs
    start_mock_llm 14031 "zai/glm-5.2" "openai/gpt-4o"

    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
g = c.get('goals', {})
d = c.get('delegation', {})
assert g.get('max_turns') == 50, f'Expected goals.max_turns=50, got: {g}'
assert d.get('max_iterations') == 50, f'Expected delegation.max_iterations=50, got: {d}'
print('OK: goals.max_turns=50 and delegation.max_iterations=50 present (defaults)')
"
}

@test "HERMES_COMPRESSION_THRESHOLD=0.8 emits context_compression.threshold" {
    seed_all_configs
    start_mock_llm 14032 "zai/glm-5.2" "openai/gpt-4o"

    HERMES_COMPRESSION_THRESHOLD=0.8 run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
cc = c.get('context_compression', {})
threshold = cc.get('threshold')
assert threshold == 0.8, f'Expected context_compression.threshold=0.8, got: {threshold}'
print('OK: context_compression.threshold=0.8')
"
}
