#!/usr/bin/env bats
# 06-fallback-chain.bats — Test OPENCODE_FALLBACK_MODEL fallback chain generation

load test_helper/common

@test "OPENCODE_FALLBACK_MODEL set generates opencode-fallback.jsonc" {
    seed_all_configs
    start_mock_llm 14081 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    OPENCODE_FALLBACK_MODEL="llama_cpp/qwen3.6-27b-q4_k_m" \
        run_generate
    [ "$status" -eq 0 ]

    local fallback_file="${GEN_DIR}/staging/opencode-fallback.jsonc"
    assert_file_exists "$fallback_file"
    assert_json_valid "$fallback_file"

    # Verify it contains fallback_models key
    python3 -c "
import json
c = json.load(open('${fallback_file}'))
assert 'fallback_models' in c, 'fallback_models key missing'
assert isinstance(c['fallback_models'], list), 'fallback_models not a list'
print(f'OK: fallback_models = {c[\"fallback_models\"]}')
"
}

@test "OPENCODE_FALLBACK_MODEL unset does NOT generate opencode-fallback.jsonc" {
    seed_all_configs
    start_mock_llm 14082 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    # Explicitly unset
    unset OPENCODE_FALLBACK_MODEL
    run_generate
    [ "$status" -eq 0 ]

    assert_file_not_exists "${GEN_DIR}/staging/opencode-fallback.jsonc"
}

@test "comma-separated list produces ordered fallback chain" {
    seed_all_configs
    start_mock_llm 14083 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    OPENCODE_FALLBACK_MODEL="z.ai/glm-5.2,llama_cpp/qwen3.6-27b-q4_k_m" \
        run_generate
    [ "$status" -eq 0 ]

    local fallback_file="${GEN_DIR}/staging/opencode-fallback.jsonc"

    python3 -c "
import json
c = json.load(open('${fallback_file}'))
fm = c['fallback_models']
assert len(fm) == 2, f'expected 2 entries, got {len(fm)}: {fm}'
assert fm[0] == 'litellm/z.ai/glm-5.2', f'index 0 wrong: {fm[0]}'
assert fm[1] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'index 1 wrong: {fm[1]}'
print('OK: ordered 2-element fallback chain')
"
}

@test "explicit opencode/ prefix is preserved in fallback chain" {
    seed_all_configs
    start_mock_llm 14084 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    OPENCODE_FALLBACK_MODEL="opencode/deepseek-v4-flash-free" \
        run_generate
    [ "$status" -eq 0 ]

    local fallback_file="${GEN_DIR}/staging/opencode-fallback.jsonc"

    python3 -c "
import json
c = json.load(open('${fallback_file}'))
fm = c['fallback_models']
assert len(fm) == 1, f'expected 1 entry, got {len(fm)}: {fm}'
assert fm[0] == 'opencode/deepseek-v4-flash-free', f'got: {fm[0]}'
print('OK: opencode/ prefix preserved')
"
}

@test "explicit litellm/ prefix is preserved in fallback chain" {
    seed_all_configs
    start_mock_llm 14085 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    OPENCODE_FALLBACK_MODEL="litellm/z.ai/glm-5.2" \
        run_generate
    [ "$status" -eq 0 ]

    local fallback_file="${GEN_DIR}/staging/opencode-fallback.jsonc"

    python3 -c "
import json
c = json.load(open('${fallback_file}'))
fm = c['fallback_models']
assert len(fm) == 1, f'expected 1 entry, got {len(fm)}: {fm}'
assert fm[0] == 'litellm/z.ai/glm-5.2', f'got: {fm[0]}'
print('OK: litellm/ prefix preserved')
"
}

@test "whitespace tolerance and trailing comma yield clean chain" {
    seed_all_configs
    start_mock_llm 14086 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    # Whitespace after comma, trailing comma
    OPENCODE_FALLBACK_MODEL="z.ai/glm-5.2, llama_cpp/qwen3.6-27b-q4_k_m," \
        run_generate
    [ "$status" -eq 0 ]

    local fallback_file="${GEN_DIR}/staging/opencode-fallback.jsonc"

    python3 -c "
import json
c = json.load(open('${fallback_file}'))
fm = c['fallback_models']
assert len(fm) == 2, f'expected 2 entries, got {len(fm)}: {fm}'
assert fm[0] == 'litellm/z.ai/glm-5.2', f'index 0 wrong: {fm[0]}'
assert fm[1] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'index 1 wrong: {fm[1]}'
print('OK: whitespace-tolerant fallback chain')
"
}

@test "hybrid cross-provider chain: opencode/ + bare entries" {
    seed_all_configs
    start_mock_llm 14087 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    OPENCODE_FALLBACK_MODEL="opencode/deepseek-v4-flash-free,llama_cpp/qwen3.6-27b-q4_k_m" \
        run_generate
    [ "$status" -eq 0 ]

    local fallback_file="${GEN_DIR}/staging/opencode-fallback.jsonc"

    python3 -c "
import json
c = json.load(open('${fallback_file}'))
fm = c['fallback_models']
assert len(fm) == 2, f'expected 2 entries, got {len(fm)}: {fm}'
assert fm[0] == 'opencode/deepseek-v4-flash-free', f'index 0 wrong: {fm[0]}'
assert fm[1] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'index 1 wrong: {fm[1]}'
print('OK: hybrid cross-provider chain')
"
}

@test "fallback chain summary appears in merge summary" {
    seed_all_configs
    start_mock_llm 14088 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    OPENCODE_FALLBACK_MODEL="llama_cpp/qwen3.6-27b-q4_k_m" \
        run_generate
    [ "$status" -eq 0 ]

    local summary="${GEN_DIR}/staging/opencode-merge-summary.txt"
    assert_file_exists "$summary"
    assert_file_contains "$summary" "fallback chain"
    assert_file_contains "$summary" "opencode-fallback.jsonc"
}

@test "single-value backward-compatible: 1-element fallback chain" {
    seed_all_configs
    start_mock_llm 14089 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    OPENCODE_FALLBACK_MODEL="llama_cpp/qwen3.6-27b-q4_k_m" \
        run_generate
    [ "$status" -eq 0 ]

    local fallback_file="${GEN_DIR}/staging/opencode-fallback.jsonc"

    python3 -c "
import json
c = json.load(open('${fallback_file}'))
fm = c['fallback_models']
assert len(fm) == 1, f'expected 1 entry, got {len(fm)}: {fm}'
assert fm[0] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'got: {fm[0]}'
print('OK: single-value backward-compatible 1-element chain')
"
}
