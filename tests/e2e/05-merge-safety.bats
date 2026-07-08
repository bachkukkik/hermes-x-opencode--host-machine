#!/usr/bin/env bats
# 05-merge-safety.bats — Test MERGE mode preserves existing blocks, dry-run safety

load test_helper/common

@test "MERGE mode preserves permission block from existing config" {
    seed_all_configs
    start_mock_llm 14061 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
perm = c.get('permission', {})
assert 'bash' in perm, 'permission.bash missing'
deny = perm['bash'].get('deny', [])
assert 'sudo' in deny, f'sudo not in deny list: {deny}'
assert 'rm -rf /' in deny, f'rm -rf / not in deny list: {deny}'
print('OK: permission block preserved')
"
}

@test "MERGE mode preserves plugin array from existing config" {
    seed_all_configs
    start_mock_llm 14062 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
plugins = c.get('plugin', [])
assert 'cc-safety-net' in plugins, f'cc-safety-net not in plugins: {plugins}'
assert 'opencode-copilot' in plugins, f'opencode-copilot not in plugins: {plugins}'
print('OK: plugin array preserved')
"
}

@test "MERGE mode preserves agent sub-block fields (mode, description)" {
    seed_all_configs
    start_mock_llm 14045 "mock-model" "zai/glm-5.2" "openai/gpt-4o"
    OPENCODE_DEFAULT_MODEL="litellm/mock-model" run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    expected_model="litellm/mock-model"
    python3 -c "
import json
expected = '${expected_model}'
c = json.load(open('${staging}'))
ab = c.get('agent', {}).get('build', {})
ap = c.get('agent', {}).get('plan', {})
# Mode and description MUST be preserved
assert ab.get('mode') == 'interactive', f'agent.build.mode={ab.get(\"mode\")}'
assert ab.get('description') == 'Build agent for coding tasks', f'agent.build.description={ab.get(\"description\")}'
assert ap.get('mode') == 'interactive', f'agent.plan.mode={ap.get(\"mode\")}'
assert ap.get('description') == 'Planning agent for strategy', f'agent.plan.description={ap.get(\"description\")}'
# model fields should be overridden to OPENCODE_DEFAULT_MODEL
assert ab.get('model') == expected, f'agent.build.model={ab.get(\"model\")}, expected={expected}'
assert ap.get('model') == expected, f'agent.plan.model={ap.get(\"model\")}, expected={expected}'
print('OK: agent sub-block fields preserved, model overridden to ' + expected)
"
}

@test "MERGE mode preserves server block from existing config" {
    seed_all_configs
    start_mock_llm 14064 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
assert 'server' in c, 'server block missing'
assert c['server'].get('port') == 4096, f'server.port={c[\"server\"].get(\"port\")}'
print('OK: server block preserved')
"
}

@test "MERGE mode preserves experimental block from existing config" {
    seed_all_configs
    start_mock_llm 14065 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
assert 'experimental' in c, 'experimental block missing'
assert c['experimental'].get('enable_codex') == True, f'experimental={c[\"experimental\"]}'
print('OK: experimental block preserved')
"
}

@test "existing litellm.models entries are preserved (union merge)" {
    seed_all_configs
    start_mock_llm 14066 "openai/gpt-4o" "anthropic/claude-sonnet-4.6" "google/gemini-pro"
    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"

    python3 -c "
import json
c = json.load(open('${staging}'))
models = c.get('provider', {}).get('litellm', {}).get('models', {})
# The pre-existing zai/glm-5.2 should still be there
assert 'zai/glm-5.2' in models, 'existing zai/glm-5.2 not preserved'
# Its limits should match what was originally seeded
assert models['zai/glm-5.2']['limit']['context'] == 1048576, 'existing model context changed'
assert models['zai/glm-5.2']['limit']['output'] == 131072, 'existing model output changed'
# New models should be added
assert 'openai/gpt-4o' in models, 'new model openai/gpt-4o not added'
print('OK: existing models preserved, new models union-merged')
"
}

@test "dry-run snapshot proves no live config files modified" {
    seed_all_configs

    # Compute checksums BEFORE
    local csum_before
    csum_before=$(sha256sum \
        "${FAKE_HOME}/.hermes/config.yaml" \
        "${FAKE_HOME}/.config/opencode/opencode.jsonc" \
        "${FAKE_HOME}/.hermes/.env" 2>/dev/null | sort)

    start_mock_llm 14067 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate --dry-run
    [ "$status" -eq 0 ]

    # Compute checksums AFTER
    local csum_after
    csum_after=$(sha256sum \
        "${FAKE_HOME}/.hermes/config.yaml" \
        "${FAKE_HOME}/.config/opencode/opencode.jsonc" \
        "${FAKE_HOME}/.hermes/.env" 2>/dev/null | sort)

    # They must be identical
    [ "$csum_before" = "$csum_after" ] || {
        echo "LIVE CONFIG MODIFIED!" >&2
        echo "Before:" >&2
        echo "$csum_before" >&2
        echo "After:" >&2
        echo "$csum_after" >&2
        false
    }
}

@test "staging dir is clean on each run (no stale artifacts)" {
    seed_all_configs
    start_mock_llm 14068 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    # First run
    run_generate
    [ "$status" -eq 0 ]

    # Write a junk file into staging
    echo "STALE" > "${GEN_DIR}/staging/stale-file.txt"

    # Second run — staging should be cleaned first
    run_generate
    [ "$status" -eq 0 ]

    # Stale file should be gone
    assert_file_not_exists "${GEN_DIR}/staging/stale-file.txt"

    # Fresh files should be there
    assert_file_exists "${GEN_DIR}/staging/opencode.jsonc"
}

@test "MERGE mode preserves other custom providers and does not duplicate litellm" {
    # Seed a config.yaml with multiple custom providers including litellm and anthropic-direct
    cat > "${FAKE_HOME}/.hermes/config.yaml" << 'YAML_EOF'
provider: custom:litellm
model:
  name: zai/glm-5.2
  default: zai/glm-5.2
custom_providers:
  - name: litellm
    base_url: http://localhost:4000
    api_key: sk-tes...2345
  - name: anthropic-direct
    base_url: https://api.anthropic.com
    api_key: sk-ant-somekey
YAML_EOF

    seed_opencode_config
    start_mock_llm 14069 "zai/glm-5.2" "openai/gpt-4o"
    run_generate
    [ "$status" -eq 0 ]

    local overlay="${GEN_DIR}/staging/config-hermes-overlay.yaml"
    python3 -c "
import yaml
c = yaml.safe_load(open('${overlay}'))
names = [cp.get('name') for cp in c['custom_providers']]
assert names.count('litellm') == 1, f'litellm duplicated/dropped: {names}'
assert 'anthropic-direct' in names, f'other provider dropped: {names}'
"
}
