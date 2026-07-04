#!/usr/bin/env bats
# 09-shell-integration.bats — Test --shell-integration and --remove-shell-integration flags
#
# Acceptance criteria:
#   AC-SI1: --shell-integration with --apply appends guarded block to rc file
#   AC-SI2: Re-running --shell-integration is idempotent (no duplicate block)
#   AC-SI3: --remove-shell-integration removes the block
#   AC-SI3b: --remove-shell-integration on absent block exits 0 (no-op)
#   AC-SI4: --shell-integration without --apply exits non-zero

load test_helper/common

# Sentinel markers as constants for test assertions
OPEN_MARKER='# >>> hermes host-config-gen env bridge (managed, do not edit) >>>'
CLOSE_MARKER='# <<< hermes host-config-gen env bridge <<<'

setup() {
    # Replicate the standard test helper setup
    TEST_TMP="$(mktemp -d /tmp/host-gen-test.XXXXXX)"
    export TEST_TMP
    FAKE_HOME="${TEST_TMP}/home"
    mkdir -p "${FAKE_HOME}/.hermes" \
             "${FAKE_HOME}/.config/opencode" \
             "${FAKE_HOME}/.local/share/opencode"
    export HOME="${FAKE_HOME}"
    GEN_DIR="${FAKE_HOME}/.hermes/host-config-gen"
    export GEN_DIR
    mkdir -p "${GEN_DIR}/lib"
    # Clean environment — prevent repo .env from leaking test defaults
    unset HERMES_YOLO_MODE HERMES_DELEGATION_MODEL HERMES_DELEGATION_PROVIDER
    unset HERMES_GOAL_MAX_TURNS HERMES_COMPRESSION_THRESHOLD
    unset OPENAI_DEFAULT_MODEL OPENCODE_DEFAULT_MODEL OPENCODE_SMALL_MODEL OPENCODE_FALLBACK_MODEL
    unset HERMES_DELEGATION_MAX_ITERATIONS
    unset OPENAI_BASE_URL
    cp "${REPO_DIR}/generate.sh" "${GEN_DIR}/"
    cp "${REPO_DIR}/lib/"*.sh     "${GEN_DIR}/lib/"
    chmod +x "${GEN_DIR}/generate.sh"

    # Shell integration test setup: create a fake .bashrc and set SHELL
    : > "${FAKE_HOME}/.bashrc"
    export SHELL=/bin/bash
}

teardown() {
    stop_mock_llm 2>/dev/null || true
    rm -rf "${TEST_TMP:-/tmp/NONEXISTENT}" 2>/dev/null || true
}

# Count occurrences of the OPEN marker in a file
_count_sentinel_opens() {
    grep -cF "$OPEN_MARKER" "$1" 2>/dev/null || echo 0
}

@test "AC-SI1: --shell-integration with --apply appends guarded block to rc file" {
    seed_all_configs
    start_mock_llm 14121 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    run_generate --apply --shell-integration
    [ "$status" -eq 0 ]

    # The rc file must contain the sentinel markers
    assert_file_contains "${FAKE_HOME}/.bashrc" "$OPEN_MARKER"
    assert_file_contains "${FAKE_HOME}/.bashrc" "$CLOSE_MARKER"

    # The source line must be present with the guarded path
    assert_file_contains "${FAKE_HOME}/.bashrc" \
        'export-env.sh" ] && source "$HOME/.hermes/host-config-gen/export-env.sh"'

    # Must have exactly one OPEN marker (idempotent by construction)
    [ "$(_count_sentinel_opens "${FAKE_HOME}/.bashrc")" -eq 1 ]
}

@test "AC-SI2: re-running --shell-integration is idempotent (no duplicate block)" {
    seed_all_configs
    start_mock_llm 14122 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    # First run
    run_generate --apply --shell-integration
    [ "$status" -eq 0 ]
    [ "$(_count_sentinel_opens "${FAKE_HOME}/.bashrc")" -eq 1 ]

    # Second run — must not duplicate
    run_generate --apply --shell-integration
    [ "$status" -eq 0 ]

    # Still exactly one OPEN marker
    [ "$(_count_sentinel_opens "${FAKE_HOME}/.bashrc")" -eq 1 ]

    # Ensure the rc file is still valid shell syntax
    bash -n "${FAKE_HOME}/.bashrc"
}

@test "AC-SI3: --remove-shell-integration removes the guarded block" {
    seed_all_configs
    start_mock_llm 14123 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    # First add the block
    run_generate --apply --shell-integration
    [ "$status" -eq 0 ]
    assert_file_contains "${FAKE_HOME}/.bashrc" "$OPEN_MARKER"

    # Then remove it
    run_generate --apply --remove-shell-integration
    [ "$status" -eq 0 ]

    # OPEN and CLOSE markers must be gone
    assert_file_not_contains "${FAKE_HOME}/.bashrc" "$OPEN_MARKER"
    assert_file_not_contains "${FAKE_HOME}/.bashrc" "$CLOSE_MARKER"
}

@test "AC-SI3b: --remove-shell-integration on absent block exits 0 (no-op)" {
    seed_all_configs
    start_mock_llm 14124 "mock-model" "zai/glm-5.2" "openai/gpt-4o" "anthropic/claude-sonnet-4.6"

    # No block added — removal should be a no-op
    run_generate --apply --remove-shell-integration
    [ "$status" -eq 0 ]

    # RC file must not contain sentinel markers
    assert_file_not_contains "${FAKE_HOME}/.bashrc" "$OPEN_MARKER"
    assert_file_not_contains "${FAKE_HOME}/.bashrc" "$CLOSE_MARKER"

    # RC file should be unchanged from initial state (empty)
    [ "$(wc -l < "${FAKE_HOME}/.bashrc")" -eq 0 ]
}

@test "AC-SI4: --shell-integration without --apply exits non-zero with clear error" {
    # No seed or mock needed — validation happens before generation
    # Also no need to run with --apply

    run_generate --shell-integration
    [ "$status" -ne 0 ]

    # Must produce a clear error message mentioning --apply
    [[ "$output" == *"--shell-integration requires --apply"* ]] || {
        echo "Expected error message to mention --apply requirement" >&2
        echo "Got: $output" >&2
        false
    }
}
