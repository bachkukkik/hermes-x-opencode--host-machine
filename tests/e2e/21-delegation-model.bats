#!/usr/bin/env bats
# 21-delegation-model.bats — Per-delegation model routing (PR #68 port)
#
# These tests verify that HERMES_DELEGATION_MODEL and HERMES_DELEGATION_PROVIDER
# conditionally write delegation.model and delegation.provider in the Hermes
# config overlay staging.
#
# Maps to PRD Section 9.4 / AC35.

load test_helper/common

@test "AC35a: HERMES_DELEGATION_MODEL emits delegation.model" {
    seed_all_configs
    start_mock_llm 14050 "zai/glm-5.2" "openai/gpt-4o"

    HERMES_DELEGATION_MODEL=openai/gpt-4o-mini run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
d = c.get('delegation', {})
assert d.get('model') == 'openai/gpt-4o-mini', f'Expected delegation.model=openai/gpt-4o-mini, got: {d}'
print('OK: delegation.model=openai/gpt-4o-mini')
"
}

@test "AC35b: HERMES_DELEGATION_PROVIDER emits delegation.provider" {
    seed_all_configs
    start_mock_llm 14051 "zai/glm-5.2" "openai/gpt-4o"

    HERMES_DELEGATION_PROVIDER=litellm run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
d = c.get('delegation', {})
assert d.get('provider') == 'litellm', f'Expected delegation.provider=litellm, got: {d}'
print('OK: delegation.provider=litellm')
"
}

@test "AC35c: Both HERMES_DELEGATION_MODEL and PROVIDER together" {
    seed_all_configs
    start_mock_llm 14052 "zai/glm-5.2" "openai/gpt-4o"

    HERMES_DELEGATION_MODEL=openai/gpt-4o-mini HERMES_DELEGATION_PROVIDER=litellm run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
d = c.get('delegation', {})
assert d.get('model') == 'openai/gpt-4o-mini', f'model={d.get(\"model\")}'
assert d.get('provider') == 'litellm', f'provider={d.get(\"provider\")}'
assert d.get('max_iterations') == 50, f'max_iterations={d.get(\"max_iterations\")}'
print('OK: delegation block has model, provider, and max_iterations')
"
}

@test "AC35d: Unset delegation model/provider does NOT emit model/provider fields" {
    seed_all_configs
    start_mock_llm 14053 "zai/glm-5.2" "openai/gpt-4o"

    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"

    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
d = c.get('delegation', {})
assert 'model' not in d, f'delegation.model should not be present when unset, got: {d}'
assert 'provider' not in d, f'delegation.provider should not be present when unset, got: {d}'
assert d.get('max_iterations') == 50, f'max_iterations={d.get(\"max_iterations\")}'
print('OK: delegation block has only max_iterations when model/provider unset')
"
}
