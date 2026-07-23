#!/usr/bin/env bats
# 28-overlay-blocks-and-small-model.bats — PR #85 alignment coverage
#
# Verifies the Hermes overlay blocks ported from the upstream Docker reference
# (web.search_backend, security.allow_lazy_installs, logging, image_gen,
# compression.threshold-by-default) and the OPENAI_SMALL_MODEL fallback tier
# feeding the OPENCODE_SMALL_MODEL resolution chain. Also covers GH_TOKEN /
# GITHUB_TOKEN alias resolution in constants.sh.

load test_helper/common

# --- Compression: always baked (default 0.76) --------------------------------

@test "AC-CMP1: unset HERMES_COMPRESSION_THRESHOLD bakes compression.threshold=0.76" {
    seed_all_configs
    start_mock_llm 14130 "zai/glm-5.2" "openai/gpt-4o"

    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"
    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
t = c.get('compression', {}).get('threshold')
assert t == 0.76, f'expected default compression.threshold=0.76, got {t!r}'
print('OK: compression.threshold defaults to 0.76')
"
}

@test "AC-CMP2: explicit HERMES_COMPRESSION_THRESHOLD overrides the default" {
    seed_all_configs
    start_mock_llm 14131 "zai/glm-5.2" "openai/gpt-4o"

    HERMES_COMPRESSION_THRESHOLD=0.9 run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"
    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
t = c.get('compression', {}).get('threshold')
assert t == 0.9, f'expected compression.threshold=0.9, got {t!r}'
print('OK: compression.threshold override honored')
"
}

# --- web / security / logging / image_gen overlay blocks ---------------------

@test "AC-WEB1: web.search_backend defaults to ddgs; security.allow_lazy_installs true" {
    seed_all_configs
    start_mock_llm 14132 "zai/glm-5.2" "openai/gpt-4o"

    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"
    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
assert c.get('web', {}).get('search_backend') == 'ddgs', c.get('web')
assert c.get('security', {}).get('allow_lazy_installs') is True, c.get('security')
print('OK: web.search_backend=ddgs, security.allow_lazy_installs=true')
"
}

@test "AC-WEB2: HERMES_WEB_SEARCH_BACKEND + HERMES_WEB_EXTRACT_BACKEND override" {
    seed_all_configs
    start_mock_llm 14133 "zai/glm-5.2" "openai/gpt-4o"

    HERMES_WEB_SEARCH_BACKEND=tavily HERMES_WEB_EXTRACT_BACKEND=trafilatura run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"
    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
assert c.get('web', {}).get('search_backend') == 'tavily', c.get('web')
assert c.get('web', {}).get('extract_backend') == 'trafilatura', c.get('web')
print('OK: web backends overridden')
"
}

@test "AC-LOG1: logging block emits DEBUG/5MB/3 backups" {
    seed_all_configs
    start_mock_llm 14134 "zai/glm-5.2" "openai/gpt-4o"

    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"
    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
lg = c.get('logging', {})
assert lg.get('level') == 'DEBUG', lg
assert lg.get('max_size_mb') == 5, lg
assert lg.get('backup_count') == 3, lg
print('OK: logging DEBUG/5/3')
"
}

@test "AC-IMG1: image_gen defaults to openai/gpt-image-2; OPENAI_IMAGE_MODEL overrides" {
    seed_all_configs
    start_mock_llm 14135 "zai/glm-5.2" "openai/gpt-4o"

    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"
    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
ig = c.get('image_gen', {})
assert ig.get('provider') == 'openai', ig
assert ig.get('model') == 'gpt-image-2', ig
print('OK: image_gen default openai/gpt-image-2')
"

    OPENAI_IMAGE_MODEL=gpt-image-3 run_generate
    [ "$status" -eq 0 ]
    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
assert c.get('image_gen', {}).get('model') == 'gpt-image-3', c.get('image_gen')
print('OK: image_gen model override honored')
"
}

# --- OPENAI_SMALL_MODEL fallback tier ----------------------------------------

@test "AC-SM1: OPENAI_SMALL_MODEL feeds small_model when OPENCODE_SMALL_MODEL unset" {
    seed_all_configs
    start_mock_llm 14136 "opencode/deepseek-v4-flash-free" "llama_cpp/qwen3.6-27b-q4_k_m"

    OPENCODE_DEFAULT_MODEL="opencode/deepseek-v4-flash-free" \
    OPENAI_SMALL_MODEL="llama_cpp/qwen3.6-27b-q4_k_m" \
        run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"
    python3 -c "
import json
c = json.load(open('${staging}'))
assert c['small_model'] == 'llama_cpp/qwen3.6-27b-q4_k_m', f'wrong small_model: {c[\"small_model\"]}'
assert c['model'] == 'opencode/deepseek-v4-flash-free', f'wrong model: {c[\"model\"]}'
print('OK: OPENAI_SMALL_MODEL fed small_model')
"
}

@test "AC-SM2: OPENCODE_SMALL_MODEL wins over OPENAI_SMALL_MODEL" {
    seed_all_configs
    start_mock_llm 14137 "opencode/deepseek-v4-flash-free" "llama_cpp/qwen3.6-27b-q4_k_m" "opencode/nemotron-3-ultra-free"

    OPENCODE_DEFAULT_MODEL="opencode/deepseek-v4-flash-free" \
    OPENCODE_SMALL_MODEL="opencode/nemotron-3-ultra-free" \
    OPENAI_SMALL_MODEL="llama_cpp/qwen3.6-27b-q4_k_m" \
        run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"
    python3 -c "
import json
c = json.load(open('${staging}'))
assert c['small_model'] == 'opencode/nemotron-3-ultra-free', f'wrong small_model: {c[\"small_model\"]}'
print('OK: OPENCODE_SMALL_MODEL takes precedence')
"
}

# --- GH_TOKEN / GITHUB_TOKEN alias -------------------------------------------

@test "AC-GH1: GH_TOKEN resolves from GITHUB_TOKEN alias in constants.sh" {
    run env -u GH_TOKEN GITHUB_TOKEN=ghp_alias_test bash -c "source '${REPO_DIR}/lib/constants.sh'; printf '%s' \"\$GH_TOKEN\""
    [ "$status" -eq 0 ]
    [ "$output" = "ghp_alias_test" ]
}

@test "AC-GH2: explicit GH_TOKEN wins over GITHUB_TOKEN alias" {
    run env GH_TOKEN=ghp_primary GITHUB_TOKEN=ghp_alias bash -c "source '${REPO_DIR}/lib/constants.sh'; printf '%s' \"\$GH_TOKEN\""
    [ "$status" -eq 0 ]
    [ "$output" = "ghp_primary" ]
}
