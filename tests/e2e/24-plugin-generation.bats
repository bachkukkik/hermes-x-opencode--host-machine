#!/usr/bin/env bats
# 24-plugin-generation.bats — Fresh-install plugin generation (GA-01 regression)
#
# Tests that when the live opencode.jsonc has no "plugin" key (fresh install),
# the generator produces the 3 default plugins, and optionally appends the
# fallback plugin when OPENCODE_FALLBACK_MODEL is set.

load test_helper/common

# --- GA-01: fresh install generates 3 base plugins ---------------------------

@test "GA-01: fresh install generates 3 base plugins when live config has no plugin key" {
    seed_all_configs
    # Overwrite opencode config with one that has permission (so validation
    # passes) but NO "plugin" key — simulating fresh install.  We use
    # seed_all_configs (not seed_empty_configs) so config.yaml has an api_key
    # that lets model discovery query the mock server, making generate.sh's
    # internal validation (TC3: >1 model in Hermes overlay) pass.
    cat > "${FAKE_HOME}/.config/opencode/opencode.jsonc" << 'JEOF'
{
  "permission": {
    "bash": {
      "deny": ["rm -rf /", "sudo"]
    }
  },
  "agent": {
    "build": {"mode": "interactive", "description": "Build agent"},
    "plan": {"mode": "interactive", "description": "Plan agent"}
  }
}
JEOF
    start_mock_llm 14120 "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"
    assert_file_exists "$staging"
    assert_json_valid "$staging"

    python3 -c "
import json
c = json.load(open('${staging}'))
plugins = c.get('plugin', [])
assert plugins, f'plugin key missing or empty: {plugins}'
assert '@tarquinen/opencode-dcp@latest' in plugins, \
    f'dcp plugin missing: {plugins}'
assert '@franlol/opencode-md-table-formatter@latest' in plugins, \
    f'md-table-formatter plugin missing: {plugins}'
assert 'cc-safety-net' in plugins, f'cc-safety-net missing: {plugins}'
assert len(plugins) == 3, f'expected exactly 3 base plugins, got {len(plugins)}: {plugins}'
print('OK: 3 base plugins generated for fresh install')
"
}

# --- GA-01: fresh install with OPENCODE_FALLBACK_MODEL -----------------------

@test "GA-01: OPENCODE_FALLBACK_MODEL appends fallback plugin to default plugins" {
    seed_all_configs
    # Same fresh-install live config — permission present, plugin absent
    cat > "${FAKE_HOME}/.config/opencode/opencode.jsonc" << 'JEOF'
{
  "permission": {
    "bash": {
      "deny": ["rm -rf /", "sudo"]
    }
  },
  "agent": {
    "build": {"mode": "interactive", "description": "Build agent"},
    "plan": {"mode": "interactive", "description": "Plan agent"}
  }
}
JEOF
    start_mock_llm 14121 "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    OPENCODE_FALLBACK_MODEL="litellm/deepseek/deepseek-v4-pro" \
        run_generate
    [ "$status" -eq 0 ]

    local staging="${GEN_DIR}/staging/opencode.jsonc"
    assert_file_exists "$staging"
    assert_json_valid "$staging"

    python3 -c "
import json
c = json.load(open('${staging}'))
plugins = c.get('plugin', [])
# Must have all 3 base plugins
assert '@tarquinen/opencode-dcp@latest' in plugins, \
    f'dcp plugin missing: {plugins}'
assert '@franlol/opencode-md-table-formatter@latest' in plugins, \
    f'md-table-formatter plugin missing: {plugins}'
assert 'cc-safety-net' in plugins, f'cc-safety-net missing: {plugins}'
# Must have the fallback plugin appended
assert 'opencode-runtime-fallback' in plugins, \
    f'fallback plugin missing: {plugins}'
assert len(plugins) == 4, \
    f'expected 4 plugins (3 base + fallback), got {len(plugins)}: {plugins}'
print('OK: 4 plugins generated (3 base + 1 fallback)')
"
}
