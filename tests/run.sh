#!/usr/bin/env bash
# tests/run.sh — bats test orchestrator (host mode, no Docker).
# Discovers tests/e2e/*.bats, runs them, reports PASS/FAIL summary,
# and exits non-zero on any failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BATS_FLAGS="${BATS_FLAGS:-}"

# --- Pre-flight checks ---

if ! command -v bats >/dev/null 2>&1; then
    echo "!! bats is not installed."
    echo "   Install with: sudo apt-get install bats"
    echo "   Or:           brew install bats-core"
    exit 1
fi

# Discover test files
shopt -s nullglob
TEST_FILES=("$SCRIPT_DIR"/e2e/*.bats)
shopt -u nullglob

if [ ${#TEST_FILES[@]} -eq 0 ]; then
    echo "!! No test files found matching tests/e2e/*.bats"
    exit 1
fi

echo "== Found ${#TEST_FILES[@]} test file(s)"
cd "$PROJECT_DIR"

echo "== Running e2e tests..."
echo ""
# Run all discovered test files. Individual test files source the
# shared helper via: load test_helper/common
bats_exit=0
bats $BATS_FLAGS "$SCRIPT_DIR/e2e/" || bats_exit=$?
echo ""

# --- Summary ---

if [ "$bats_exit" -ne 0 ]; then
    echo "== FAIL: e2e test suite had failures (bats exit $bats_exit)"
    exit 1
fi

echo "== PASS: All tests passed"
exit 0
