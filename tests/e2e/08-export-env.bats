#!/usr/bin/env bats
# 08-export-env.bats — Test export-env.sh generation and deployment
#
# Acceptance criteria:
#   AC-EXP1: staging/export-env.sh contains export OPENAI_API_KEY= and export OPENAI_BASE_URL=
#   AC-EXP2: --apply dry-run lists export-env.sh in apply plan
#   AC-EXP3: generate.sh source contains export OPENAI_API_KEY OPENAI_BASE_URL in export bridge

load test_helper/common

@test "AC-EXP1: generate.sh --dry-run creates staging/export-env.sh with OPENAI_API_KEY and OPENAI_BASE_URL" {
    seed_all_configs
    start_mock_llm 14108 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    run_generate --dry-run
    [ "$status" -eq 0 ]

    # Staging export-env.sh must exist
    assert_file_exists "${GEN_DIR}/staging/export-env.sh"

    # Must contain the expected export lines
    assert_file_contains "${GEN_DIR}/staging/export-env.sh" "export OPENAI_API_KEY="
    assert_file_contains "${GEN_DIR}/staging/export-env.sh" "export OPENAI_BASE_URL="
    assert_file_contains "${GEN_DIR}/staging/export-env.sh" "export OPENCODE_DEFAULT_MODEL="
    assert_file_contains "${GEN_DIR}/staging/export-env.sh" "export OPENCODE_ZEN_API_KEY="

    # Must be shell-syntax valid
    bash -n "${GEN_DIR}/staging/export-env.sh" || {
        echo "export-env.sh has bash syntax errors" >&2
        false
    }
}

@test "AC-EXP2: generate.sh --apply --dry-run lists export-env.sh in apply plan" {
    seed_all_configs
    start_mock_llm 14109 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    run_generate --apply --dry-run
    [ "$status" -eq 0 ]

    # Apply plan must mention export-env.sh by name
    [[ "$output" == *"export-env.sh"* ]] || {
        echo "Expected 'export-env.sh' to appear in apply dry-run output" >&2
        echo "Got: $output" >&2
        false
    }

    # The apply plan should list the deploy path — verify it mentions the live dest
    [[ "$output" == *"host-config-gen/export-env.sh"* ]] || {
        echo "Expected apply plan to show deploy to host-config-gen/export-env.sh" >&2
        echo "Got: $output" >&2
        false
    }
}

@test "AC-EXP3: generate.sh source has export OPENAI_API_KEY OPENAI_BASE_URL in export bridge" {
    # Check the source file directly — no generator run needed
    assert_file_contains "${REPO_DIR}/generate.sh" \
        "export OPENAI_API_KEY OPENAI_BASE_URL"
}
