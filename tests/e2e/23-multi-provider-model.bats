#!/usr/bin/env bats
# 23-multi-provider-model.bats — Multi-provider model routing (PRD Section 11.4)
#
# Tests for acceptance criteria AC40–AC46:
#   AC40 — llama_cpp/* default model produces correct model field
#   AC41 — opencode/* default model routes via Zen
#   AC42 — litellm/* default model routes via litellm
#   AC43 — OPENCODE_SMALL_MODEL differs from OPENCODE_DEFAULT_MODEL
#   AC44 — OPENCODE_FALLBACK_MODEL multi-provider chain produces correct fallback file
#   AC45 — bare model id + OPENAI creds present -> resolves to litellm/
#   AC46 — bare model id + no OPENAI creds -> resolves to opencode/ (Zen)

load test_helper/common

# --- AC40: llama_cpp default model -------------------------------------------

@test "AC40: OPENCODE_DEFAULT_MODEL=llama_cpp/qwen3.6-27b-q4_k_m produces correct model field" {
    seed_all_configs
    start_mock_llm 14100 "llama_cpp/qwen3.6-27b-q4_k_m" "zai/glm-5.2" "openai/gpt-4o"

    OPENCODE_DEFAULT_MODEL="llama_cpp/qwen3.6-27b-q4_k_m" \
        run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"
    assert_file_exists "$staging"
    assert_json_valid "$staging"

    python3 -c "
import json
c = json.load(open('${staging}'))
assert c['model'] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'wrong model: {c[\"model\"]}'
assert c['small_model'] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'wrong small_model: {c[\"small_model\"]}'
assert c['agent']['build']['model'] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'wrong agent.build.model'
assert c['agent']['plan']['model'] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'wrong agent.plan.model'
# llama_cpp provider block must exist so OpenCode can resolve the model
assert 'llama_cpp' in c['provider'], 'missing provider.llama_cpp'
assert c['provider']['llama_cpp']['npm'] == '@ai-sdk/openai-compatible'
print('OK: llama_cpp model field correct, provider block present')
"
}

# --- AC41: opencode (Zen) default model --------------------------------------

@test "AC41: OPENCODE_DEFAULT_MODEL=opencode/deepseek-v4-flash-free routes via Zen" {
    seed_all_configs
    start_mock_llm 14101 "opencode/deepseek-v4-flash-free" "zai/glm-5.2"

    OPENCODE_DEFAULT_MODEL="opencode/deepseek-v4-flash-free" \
        run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
assert c['model'] == 'opencode/deepseek-v4-flash-free', f'wrong model: {c[\"model\"]}'
assert c['small_model'] == 'opencode/deepseek-v4-flash-free', f'wrong small_model'
assert c['agent']['build']['model'] == 'opencode/deepseek-v4-flash-free'
assert c['agent']['plan']['model'] == 'opencode/deepseek-v4-flash-free'
# Must use the opencode provider (Zen auth)
assert c['provider']['opencode']['options']['apiKey'] == '{env:OPENCODE_ZEN_API_KEY}'
print('OK: opencode/Zen model field correct, uses Zen auth')
"
}

# --- AC42: litellm default model ---------------------------------------------

@test "AC42: OPENCODE_DEFAULT_MODEL=litellm/deepseek/deepseek-v4-pro routes via litellm" {
    seed_all_configs
    start_mock_llm 14102 "litellm/deepseek/deepseek-v4-pro" "zai/glm-5.2"

    OPENCODE_DEFAULT_MODEL="litellm/deepseek/deepseek-v4-pro" \
        run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
assert c['model'] == 'litellm/deepseek/deepseek-v4-pro', f'wrong model: {c[\"model\"]}'
assert c['small_model'] == 'litellm/deepseek/deepseek-v4-pro', f'wrong small_model'
assert c['agent']['build']['model'] == 'litellm/deepseek/deepseek-v4-pro'
assert c['agent']['plan']['model'] == 'litellm/deepseek/deepseek-v4-pro'
# Must have litellm provider block with correct auth
assert c['provider']['litellm']['options']['apiKey'] == '{env:OPENAI_API_KEY}'
print('OK: litellm model field correct, uses litellm auth')
"
}

# --- AC43: OPENCODE_SMALL_MODEL differs from default -------------------------

@test "AC43: OPENCODE_SMALL_MODEL differs from OPENCODE_DEFAULT_MODEL and both are correct" {
    seed_all_configs
    start_mock_llm 14103 "opencode/deepseek-v4-flash-free" "zai/glm-5.2" "llama_cpp/qwen3.6-27b-q4_k_m"

    OPENCODE_DEFAULT_MODEL="opencode/deepseek-v4-flash-free" \
    OPENCODE_SMALL_MODEL="llama_cpp/qwen3.6-27b-q4_k_m" \
        run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
assert c['model'] == 'opencode/deepseek-v4-flash-free', f'wrong model: {c[\"model\"]}'
assert c['small_model'] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'wrong small_model: {c[\"small_model\"]}'
# Agent sub-models follow OPENCODE_DEFAULT_MODEL (not small_model)
assert c['agent']['build']['model'] == 'opencode/deepseek-v4-flash-free'
assert c['agent']['plan']['model'] == 'opencode/deepseek-v4-flash-free'
# Verify they are actually different
assert c['model'] != c['small_model'], 'model and small_model should differ'
print('OK: model and small_model differ correctly')
"
}

# --- AC44: OPENCODE_FALLBACK_MODEL multi-provider chain ----------------------

@test "AC44: OPENCODE_FALLBACK_MODEL with multi-provider chain produces correct opencode-fallback.jsonc" {
    seed_all_configs
    start_mock_llm 14104 "opencode/deepseek-v4-flash-free" "litellm/deepseek/deepseek-v4-pro" "llama_cpp/qwen3.6-27b-q4_k_m" "zai/glm-5.2"

    OPENCODE_DEFAULT_MODEL="opencode/deepseek-v4-flash-free" \
    OPENCODE_FALLBACK_MODEL="litellm/deepseek/deepseek-v4-pro,llama_cpp/qwen3.6-27b-q4_k_m,zai/glm-5.2" \
        run_generate
    [ "$status" -eq 0 ]

    local fallback_file="${GEN_DIR}/staging/opencode-fallback.jsonc"
    assert_file_exists "$fallback_file"
    assert_json_valid "$fallback_file"

    python3 -c "
import json
c = json.load(open('${fallback_file}'))
assert 'fallback_models' in c, 'missing fallback_models key'
fm = c['fallback_models']
assert len(fm) == 3, f'expected 3 fallback entries, got {len(fm)}: {fm}'
# litellm/ prefix preserved explicitly
assert fm[0] == 'litellm/deepseek/deepseek-v4-pro', f'index 0 wrong: {fm[0]}'
# llama_cpp/ prefix preserved explicitly
assert fm[1] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'index 1 wrong: {fm[1]}'
# bare model (no prefix) gets auto-prefixed with litellm/
assert fm[2] == 'litellm/zai/glm-5.2', f'index 2 wrong (bare -> litellm): {fm[2]}'
print('OK: multi-provider fallback chain correct — litellm + llama_cpp + bare->litellm')
"

    # Also verify the merge summary mentions the fallback chain
    local summary="${GEN_DIR}/staging/opencode-merge-summary.txt"
    assert_file_exists "$summary"
    assert_file_contains "$summary" "fallback chain"
    assert_file_contains "$summary" "opencode-fallback.jsonc"
}

# --- AC45: bare model id + OPENAI creds present -> resolves to litellm/ ------

@test "AC45: bare model id + OPENAI creds present -> resolves to litellm/" {
    seed_all_configs
    start_mock_llm 14105 "deepseek-v4-flash-free" "zai/glm-5.2"

    # BARE model id — no provider prefix. With OPENAI creds present (mock server
    # implies OPENAI_BASE_URL is set), this must resolve to litellm/.
    OPENCODE_DEFAULT_MODEL="deepseek-v4-flash-free" \
        run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
assert c['model'] == 'litellm/deepseek-v4-flash-free', f'wrong model: {c[\"model\"]} — bare id should resolve to litellm/ when OPENAI creds present'
assert c['small_model'] == 'litellm/deepseek-v4-flash-free', f'wrong small_model: {c[\"small_model\"]}'
print('OK: bare id + creds -> litellm/ prefix applied')
"
}

# --- AC46: bare model id + no OPENAI creds -> resolves to opencode/ (Zen) ----

@test "AC46: bare model id + no OPENAI creds -> resolves to opencode/ (Zen)" {
    seed_all_configs
    start_mock_llm 14106 "deepseek-v4-flash-free" "zai/glm-5.2"

    # BARE model id with NO OpenAI creds — must resolve to opencode/ (Zen).
    # We unset OPENAI_BASE_URL and OPENAI_API_KEY to simulate Zen-only setup.
    # Note: start_mock_llm sets OPENAI_BASE_URL, so we must explicitly unset it.
    OPENAI_BASE_URL="" OPENAI_API_KEY="" \
    OPENCODE_DEFAULT_MODEL="deepseek-v4-flash-free" \
        run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
assert c['model'] == 'opencode/deepseek-v4-flash-free', f'wrong model: {c[\"model\"]} — bare id should resolve to opencode/ when no OPENAI creds'
assert c['small_model'] == 'opencode/deepseek-v4-flash-free', f'wrong small_model: {c[\"small_model\"]}'
print('OK: bare id + no creds -> opencode/ prefix applied (Zen fallback)')
"
}
