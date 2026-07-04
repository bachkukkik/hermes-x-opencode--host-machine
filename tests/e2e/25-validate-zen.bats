#!/usr/bin/env bats
# 25-validate-zen.bats — Test validate_zen_key validation
#
# Acceptance criteria:
#   AC-ZEN1: validate_zen_key returns 0 when OPENCODE_ZEN_API_KEY is set and valid
#   AC-ZEN2: validate_zen_key returns 0 when OPENCODE_ZEN_API_KEY is unset (non-fatal)

load test_helper/common

@test "AC-ZEN1: validate_zen_key returns 0 when OPENCODE_ZEN_API_KEY is set" {
    seed_all_configs
    source "${GEN_DIR}/lib/validate-zen.sh"
    export OPENCODE_ZEN_API_KEY="sk-zen-test-key-12345"
    run validate_zen_key
    [ "$status" -eq 0 ]
}

@test "AC-ZEN2: validate_zen_key returns 0 when OPENCODE_ZEN_API_KEY is unset" {
    seed_all_configs
    source "${GEN_DIR}/lib/validate-zen.sh"
    unset OPENCODE_ZEN_API_KEY
    run validate_zen_key
    [ "$status" -eq 0 ]
}
