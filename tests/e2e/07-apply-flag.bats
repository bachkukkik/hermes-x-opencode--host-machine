#!/usr/bin/env bats
# 07-apply-flag.bats — Test generate.sh --apply flag (staging → live with .bak backups)

load test_helper/common

@test "generate.sh --apply exit code 0" {
    seed_all_configs
    start_mock_llm 14101 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate --apply
    [ "$status" -eq 0 ]
}

@test "generate.sh --apply --dry-run exit code 0" {
    seed_all_configs
    start_mock_llm 14102 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"
    run_generate --apply --dry-run
    [ "$status" -eq 0 ]
}

@test "generate.sh --apply --dry-run shows apply plan without writing" {
    seed_all_configs
    start_mock_llm 14103 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    # Snapshot live file checksums before run
    local orig_opencode orig_hermes
    orig_opencode=$(sha256sum "${FAKE_HOME}/.config/opencode/opencode.jsonc" | awk '{print $1}')
    orig_hermes=$(sha256sum "${FAKE_HOME}/.hermes/config.yaml" | awk '{print $1}')

    run_generate --apply --dry-run
    [ "$status" -eq 0 ]

    # Output should contain apply plan markers
    [[ "$output" == *"Would apply"* ]] || {
        echo "Expected 'Would apply' in dry-run output" >&2
        echo "Got: $output" >&2
        false
    }
    [[ "$output" == *"Would backup"* ]] || {
        echo "Expected 'Would backup' in dry-run output" >&2
        echo "Got: $output" >&2
        false
    }

    # Live files must NOT have changed
    local new_opencode new_hermes
    new_opencode=$(sha256sum "${FAKE_HOME}/.config/opencode/opencode.jsonc" | awk '{print $1}')
    new_hermes=$(sha256sum "${FAKE_HOME}/.hermes/config.yaml" | awk '{print $1}')
    [ "$orig_opencode" = "$new_opencode" ] || {
        echo "OpenCode config was modified by --apply --dry-run!" >&2
        false
    }
    [ "$orig_hermes" = "$new_hermes" ] || {
        echo "Hermes config was modified by --apply --dry-run!" >&2
        false
    }

    # No .bak files should exist after dry-run
    assert_file_not_exists "${FAKE_HOME}/.config/opencode/opencode.jsonc.bak"
    assert_file_not_exists "${FAKE_HOME}/.hermes/config.yaml.bak"
    assert_file_not_exists "${FAKE_HOME}/.local/share/opencode/auth.json.bak"
}

@test "generate.sh --apply creates .bak backups before overwriting" {
    seed_all_configs
    start_mock_llm 14104 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    run_generate --apply
    [ "$status" -eq 0 ]

    # .bak files must exist for files that existed before --apply
    assert_file_exists "${FAKE_HOME}/.config/opencode/opencode.jsonc.bak"
    assert_file_exists "${FAKE_HOME}/.hermes/config.yaml.bak"
}

@test "generate.sh --apply overwrites live config files with staging content" {
    # Seed a distinctive marker in the original live config
    seed_all_configs
    start_mock_llm 14105 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    # The original opencode.jsonc has "deepseek-v4-flash-free" — staging should
    # have the same model (default), but the staging content is freshly generated
    # and differs in structure from the seeded config.

    run_generate --apply
    [ "$status" -eq 0 ]

    # Live opencode.jsonc must be valid JSON after apply
    assert_json_valid "${FAKE_HOME}/.config/opencode/opencode.jsonc"

    # Live Hermes config must be valid YAML after apply
    assert_yaml_valid "${FAKE_HOME}/.hermes/config.yaml"

    # Live auth.json must exist and be valid JSON
    assert_file_exists "${FAKE_HOME}/.local/share/opencode/auth.json"
    assert_json_valid "${FAKE_HOME}/.local/share/opencode/auth.json"

    # Applied configs must match staging
    local staging_opencode staging_hermes staging_auth
    staging_opencode=$(sha256sum "${GEN_DIR}/staging/opencode.jsonc" | awk '{print $1}')
    staging_hermes=$(sha256sum "${GEN_DIR}/staging/config-hermes-overlay.yaml" | awk '{print $1}')
    staging_auth=$(sha256sum "${GEN_DIR}/staging/auth.json" | awk '{print $1}')

    local live_opencode live_hermes live_auth
    live_opencode=$(sha256sum "${FAKE_HOME}/.config/opencode/opencode.jsonc" | awk '{print $1}')
    live_hermes=$(sha256sum "${FAKE_HOME}/.hermes/config.yaml" | awk '{print $1}')
    live_auth=$(sha256sum "${FAKE_HOME}/.local/share/opencode/auth.json" | awk '{print $1}')

    [ "$staging_opencode" = "$live_opencode" ] || {
        echo "Live opencode.jsonc does not match staging!" >&2
        false
    }
    [ "$staging_hermes" = "$live_hermes" ] || {
        echo "Live config.yaml does not match staging!" >&2
        false
    }
    [ "$staging_auth" = "$live_auth" ] || {
        echo "Live auth.json does not match staging!" >&2
        false
    }
}

@test "generate.sh --apply shows apply output markers" {
    seed_all_configs
    start_mock_llm 14106 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    run_generate --apply
    [ "$status" -eq 0 ]

    [[ "$output" == *"Mode: APPLY"* ]] || {
        echo "Expected 'Mode: APPLY' in output" >&2
        false
    }
    [[ "$output" == *"Backed up"* ]] || {
        echo "Expected 'Backed up' in output" >&2
        false
    }
    [[ "$output" == *"Applied"* ]] || {
        echo "Expected 'Applied' in output" >&2
        false
    }
}

@test "generate.sh --apply --dry-run shows Mode: APPLY-DRY-RUN" {
    seed_all_configs
    start_mock_llm 14107 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    run_generate --apply --dry-run
    [ "$status" -eq 0 ]

    [[ "$output" == *"Mode: APPLY-DRY-RUN"* ]] || {
        echo "Expected 'Mode: APPLY-DRY-RUN' in output" >&2
        false
    }
}
