#!/usr/bin/env bats
# 26-dcp-config.bats — DCP (dynamic context pruning) config generation
#
# The @tarquinen/opencode-dcp plugin defaults compress.maxContextLimit to a hard
# 100_000 tokens regardless of the active model, so a 1M-context model gets
# compression-nudged at ~10% fill. generate_dcp_staging() writes a managed
# dcp.jsonc whose compress thresholds are a PERCENTAGE of each model's own
# context window (DCP resolves "X%" per active model), driven by
# OPENCODE_COMPRESSION_THRESHOLD (default 0.76, mirroring Hermes).

load test_helper/common

_stage_dcp() { echo "${GEN_DIR}/staging/dcp.jsonc"; }

@test "DCP1: default threshold writes 76% maxContextLimit + valid JSON + \$schema" {
    unset OPENCODE_COMPRESSION_THRESHOLD
    seed_all_configs
    start_mock_llm 14070 "deepseek/deepseek-v4-pro" "zai/glm-5.2"
    run_generate
    [ "$status" -eq 0 ]

    local staging; staging="$(_stage_dcp)"
    assert_file_exists "${staging}"
    assert_json_valid "${staging}"
    python3 -c "
import json
d = json.load(open('${staging}'))
assert d.get('compress', {}).get('maxContextLimit') == '76%', d
assert d.get('compress', {}).get('minContextLimit') == '38%', d
assert 'schema' in ''.join(d.keys()).lower() or '\$schema' in d, d
print('OK: default DCP thresholds 76%/38%')
"
}

@test "DCP2: OPENCODE_COMPRESSION_THRESHOLD=0.9 writes 90% maxContextLimit" {
    export OPENCODE_COMPRESSION_THRESHOLD=0.9
    seed_all_configs
    start_mock_llm 14071 "deepseek/deepseek-v4-pro"
    run_generate
    [ "$status" -eq 0 ]

    local staging; staging="$(_stage_dcp)"
    python3 -c "
import json
d = json.load(open('${staging}'))
assert d['compress']['maxContextLimit'] == '90%', d
assert d['compress']['minContextLimit'] == '45%', d
print('OK: threshold 0.9 -> 90%/45%')
"
}

@test "DCP3: existing dcp.jsonc keys are preserved (surgical merge)" {
    seed_all_configs
    cat > "${FAKE_HOME}/.config/opencode/dcp.jsonc" << 'DCPEOF'
{
  "enabled": true,
  "debug": true,
  "compress": {
    "nudgeFrequency": 3,
    "maxContextLimit": 100000
  },
  "strategies": { "deduplication": { "enabled": false } }
}
DCPEOF
    start_mock_llm 14072 "deepseek/deepseek-v4-pro"
    run_generate
    [ "$status" -eq 0 ]

    local staging; staging="$(_stage_dcp)"
    python3 -c "
import json
d = json.load(open('${staging}'))
# Overridden target keys
assert d['compress']['maxContextLimit'] == '76%', d
# Preserved untouched keys
assert d['debug'] is True, d
assert d['compress']['nudgeFrequency'] == 3, d
assert d['strategies']['deduplication']['enabled'] is False, d
print('OK: unrelated dcp.jsonc keys preserved')
"
}

@test "DCP4: out-of-range threshold falls back to default 0.76" {
    export OPENCODE_COMPRESSION_THRESHOLD=1.5
    seed_all_configs
    start_mock_llm 14073 "deepseek/deepseek-v4-pro"
    run_generate
    [ "$status" -eq 0 ]

    local staging; staging="$(_stage_dcp)"
    python3 -c "
import json
d = json.load(open('${staging}'))
assert d['compress']['maxContextLimit'] == '76%', d
print('OK: out-of-range threshold clamped to default')
"
}
