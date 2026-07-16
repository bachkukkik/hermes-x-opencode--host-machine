#!/usr/bin/env bats
# 27-max-tokens.bats — model.max_tokens OUTPUT cap generation
#
# These tests verify that HERMES_MAX_TOKENS bakes model.max_tokens into the
# Hermes config overlay. This is the response-length ceiling Hermes sends per
# request; leaving it unset lets the upstream provider apply a small default
# that truncates long responses (finish_reason='length'), including delegation
# subagents. Subagents inherit the parent max_tokens, so this fixes them too.

load test_helper/common

@test "AC36a: HERMES_MAX_TOKENS emits model.max_tokens as int" {
    seed_all_configs
    start_mock_llm 14060 "zai/glm-5.2" "openai/gpt-4o"

    HERMES_MAX_TOKENS=32000 run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
m = c.get('model', {})
assert m.get('max_tokens') == 32000, f'Expected model.max_tokens=32000 (int), got: {m.get(\"max_tokens\")!r}'
assert isinstance(m.get('max_tokens'), int), 'max_tokens must be an int, not a string'
print('OK: model.max_tokens=32000')
"
}

@test "AC36b: Unset HERMES_MAX_TOKENS emits the constants.sh default 262144" {
    # Parity with the Docker reference: HERMES_MAX_TOKENS defaults to 262144 in
    # constants.sh, so an unset var still bakes model.max_tokens (prevents
    # provider-default truncation out of the box).
    seed_all_configs
    start_mock_llm 14061 "zai/glm-5.2" "openai/gpt-4o"

    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
m = c.get('model', {})
assert m.get('max_tokens') == 262144, f'Expected default model.max_tokens=262144, got: {m.get(\"max_tokens\")!r}'
assert isinstance(m.get('max_tokens'), int), 'max_tokens must be an int, not a string'
print('OK: model.max_tokens defaults to 262144')
"
}

@test "AC36c: Non-integer HERMES_MAX_TOKENS is ignored (no crash, no key)" {
    seed_all_configs
    start_mock_llm 14062 "zai/glm-5.2" "openai/gpt-4o"

    HERMES_MAX_TOKENS=not-a-number run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
m = c.get('model', {})
assert 'max_tokens' not in m, f'invalid max_tokens should be ignored, got: {m.get(\"max_tokens\")!r}'
print('OK: invalid max_tokens ignored')
"
}
