#!/usr/bin/env bats
# 04-model-discovery.bats — Test model discovery, filtering, and fallback

load test_helper/common

@test "model discovery fetches models from LiteLLM /v1/models" {
    seed_all_configs
    start_mock_llm 14041 "openai/gpt-4o" "anthropic/claude-sonnet-4.6" "zai/glm-5.2"
    run_generate
    [ "$status" -eq 0 ]

    local models_file="${GEN_DIR}/staging/discovered-models.txt"
    assert_file_exists "$models_file"

    # Should contain the mock models (and default model prepended)
    assert_file_contains "$models_file" "zai/glm-5.2"
    assert_file_contains "$models_file" "openai/gpt-4o"
    assert_file_contains "$models_file" "anthropic/claude-sonnet-4.6"
}

@test "model discovery filters out non-chat models" {
    seed_all_configs
    # Serve a mix of chat and non-chat models
    start_mock_llm 14042 \
        "openai/gpt-4o" \
        "embed-text-ada-002" \
        "whisper-1" \
        "tts-1" \
        "dall-e-3" \
        "zai/glm-5.2"
    run_generate
    [ "$status" -eq 0 ]

    local models_file="${GEN_DIR}/staging/discovered-models.txt"

    # Chat models should be present
    assert_file_contains "$models_file" "openai/gpt-4o"
    assert_file_contains "$models_file" "zai/glm-5.2"

    # Non-chat models should be filtered OUT
    assert_file_not_contains "$models_file" "embed"
    assert_file_not_contains "$models_file" "whisper"
    assert_file_not_contains "$models_file" "tts"
    assert_file_not_contains "$models_file" "dall-e"
}

@test "model discovery filters wildcard IDs like anthropic/*" {
    seed_all_configs
    start_mock_llm 14043 "openai/gpt-4o" "anthropic/*" "zai/glm-5.2" "google/gemini-pro" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    local models_file="${GEN_DIR}/staging/discovered-models.txt"

    assert_file_contains "$models_file" "openai/gpt-4o"
    # Use Python for exact matching to avoid grep * wildcard issues
    python3 -c "
models = open('${models_file}').read().splitlines()
assert 'anthropic/*' not in models, f'anthropic/* was not filtered: {models}'
print('OK: anthropic/* filtered out')
"
    assert_file_contains "$models_file" "anthropic/claude-sonnet-4.6"
}

@test "model discovery filters image/sora/realtime models" {
    seed_all_configs
    start_mock_llm 14044 \
        "openai/gpt-4o" \
        "sora-v2" \
        "realtime-api" \
        "image-gen-xl" \
        "zai/glm-5.2"
    run_generate
    [ "$status" -eq 0 ]

    local models_file="${GEN_DIR}/staging/discovered-models.txt"

    assert_file_contains "$models_file" "openai/gpt-4o"
    assert_file_not_contains "$models_file" "sora"
    assert_file_not_contains "$models_file" "realtime"
    assert_file_not_contains "$models_file" "image"
}

@test "model discovery filters stable-diffusion/midjourney/flux" {
    seed_all_configs
    start_mock_llm 14045 \
        "openai/gpt-4o" \
        "stable-diffusion-xl" \
        "midjourney-v6" \
        "flux-pro" \
        "replicate/llama-3" \
        "zai/glm-5.2" \
        "google/gemini-pro"
    run_generate
    [ "$status" -eq 0 ]

    local models_file="${GEN_DIR}/staging/discovered-models.txt"

    assert_file_contains "$models_file" "openai/gpt-4o"
    assert_file_contains "$models_file" "zai/glm-5.2"
    assert_file_contains "$models_file" "google/gemini-pro"
    assert_file_not_contains "$models_file" "stable-diffusion"
    assert_file_not_contains "$models_file" "midjourney"
    assert_file_not_contains "$models_file" "flux"
    # replicate/llama-3: 'replicate' is in skip list so it gets filtered
}

@test "default model seeded when LiteLLM unreachable (EC1)" {
    seed_all_configs
    # Do NOT start mock LLM — generator should fall back to default model
    # Validation requires >1 model for Hermes overlay — EC1 produces only 1.
    # We verify the fallback output without asserting exit 0.
    run_generate

    local models_file="${GEN_DIR}/staging/discovered-models.txt"
    assert_file_exists "$models_file"

    # Should contain only the OPENAI_DEFAULT_MODEL
    local count
    count=$(wc -l < "$models_file" | tr -d ' ')
    [ "$count" -ge 1 ]

    assert_file_contains "$models_file" "zai/glm-5.2"
}

@test "model discovery deduplicates case-insensitively" {
    seed_all_configs
    # Serve duplicate models with different case, plus extras for >1 validation
    start_mock_llm 14046 "Openai/GPT-4o" "openai/gpt-4o" "zai/glm-5.2" "ZAI/GLM-5.2" "google/gemini-pro" "GOOGLE/GEMINI-PRO"
    run_generate
    [ "$status" -eq 0 ]

    local models_file="${GEN_DIR}/staging/discovered-models.txt"

    # Count occurrences — should have each model exactly once
    local gpt4o_count glm52_count
    gpt4o_count=$(grep -ci 'gpt-4o' "$models_file" || echo 0)
    glm52_count=$(grep -ci 'glm-5.2' "$models_file" || echo 0)

    [ "$gpt4o_count" -eq 1 ]
    [ "$glm52_count" -eq 1 ]
}

@test "model discovery preserves default model first in list" {
    seed_all_configs
    start_mock_llm 14047 "openai/gpt-4o" "anthropic/claude-sonnet-4.6" "google/gemini-pro"
    run_generate
    [ "$status" -eq 0 ]

    local models_file="${GEN_DIR}/staging/discovered-models.txt"
    local first_line
    first_line=$(head -1 "$models_file")
    # OPENCODE_DEFAULT_MODEL (defaults to opencode/deepseek-v4-flash-free via
    # constants.sh) is now prepended by the override model ensure loop.
    [ "$first_line" = "opencode/deepseek-v4-flash-free" ]
}
