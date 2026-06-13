#!/usr/bin/env bash
# generate.sh — host-level Hermes × OpenCode config generator
#
# "Copycat" of the Docker stack's entrypoint.sh config-generation pipeline,
# adapted for bare-metal host installation. Discovers models from the LiteLLM
# proxy and generates MERGED config overlays into a staging directory.
#
# SAFETY: This script NEVER touches live config files. All output goes to
# ~/.hermes/host-config-gen/staging/. The orchestrator (or you) reviews and
# applies the staging files in a separate step.
#
# Usage:
#   bash generate.sh             # full run: discover + generate all staging
#   bash generate.sh --dry-run   # same, plus validation assertions + live-file
#                                # checksum verification (no writes outside staging)
#   bash generate.sh --help      # show this help
#
# Strict requirement: OpenCode defaults to opencode/deepseek-v4-flash-free
# (free Zen model) so Hermes->OpenCode delegation burns no paid quota.

set -euo pipefail

# --- Locate lib/ relative to this script -------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# --- Parse args --------------------------------------------------------------
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            grep '^#' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg (try --help)" >&2
            exit 1
            ;;
    esac
done

# --- Source lib modules ------------------------------------------------------
# shellcheck source=lib/constants.sh
source "${LIB_DIR}/constants.sh"
# shellcheck source=lib/model-discovery.sh
source "${LIB_DIR}/model-discovery.sh"
# shellcheck source=lib/config-opencode.sh
source "${LIB_DIR}/config-opencode.sh"
# shellcheck source=lib/config-hermes.sh
source "${LIB_DIR}/config-hermes.sh"
# shellcheck source=lib/env-auth.sh
source "${LIB_DIR}/env-auth.sh"

echo "============================================================"
echo " Hermes x OpenCode host config generator"
echo " Mode: $([ "$DRY_RUN" = true ] && echo 'DRY-RUN (staging + validation)' || echo 'GENERATE (staging only)')"
echo " LiteLLM:  ${LITELLM_BASE_URL}"
echo " Free model: ${OPENCODE_FREE_MODEL}"
echo "============================================================"
echo

# --- DRY-RUN: snapshot live file checksums (prove no mutation) --------------
LIVE_CHECKSUMS=""
snapshot_live_checksums() {
    local files=("${CONFIG}" "${OPENCODE_CONFIG}" "${HERMES_ENV}" "${OPENCODE_AUTH}")
    LIVE_CHECKSUMS=""
    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            local sum
            sum=$(sha256sum "$f" | awk '{print $1}')
            LIVE_CHECKSUMS="${LIVE_CHECKSUMS}${f}=${sum}"$'\n'
        fi
    done
}
verify_live_checksums() {
    local errors=0
    while IFS='=' read -r f expected; do
        [ -z "$f" ] && continue
        if [ -f "$f" ]; then
            local actual
            actual=$(sha256sum "$f" | awk '{print $1}')
            if [ "$actual" != "$expected" ]; then
                echo "!! CHECKSUM MISMATCH: $f was modified!" >&2
                errors=$((errors + 1))
            fi
        fi
    done <<< "$LIVE_CHECKSUMS"
    if [ "$errors" -eq 0 ]; then
        echo ">> Verified: no live config files were modified."
    else
        echo "!! FAILED: $errors live file(s) were modified!" >&2
        return 1
    fi
}

if [ "$DRY_RUN" = true ]; then
    snapshot_live_checksums
fi

# --- Clean staging dir -------------------------------------------------------
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# --- Phase 1: Model discovery ------------------------------------------------
discover_models
echo

# --- Phase 2: OpenCode config merge (provider.opencode + litellm + models) ---
echo "-- Generating OpenCode staging (MERGE mode)..."
generate_opencode_staging
echo

# --- Phase 3: Hermes config overlay (custom_providers models map) -----------
echo "-- Generating Hermes config overlay..."
generate_hermes_overlay
echo

# --- Phase 4: auth.json staging ---------------------------------------------
echo "-- Generating auth.json staging..."
generate_auth_staging
echo

# --- Validation --------------------------------------------------------------
echo "============================================================"
echo " VALIDATION"
echo "============================================================"

PASS=0
FAIL=0
_pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
_fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

# TC1: bash syntax on all scripts
for script in "$0" "${LIB_DIR}"/*.sh; do
    if bash -n "$script" 2>/dev/null; then
        _pass "bash -n $(basename "$script")"
    else
        _fail "bash -n $(basename "$script")"
    fi
done

# TC4: staging opencode.jsonc is valid JSON
if python3 -m json.tool "${STAGING_OPENCODE}" >/dev/null 2>&1; then
    _pass "staging/opencode.jsonc valid JSON"
else
    _fail "staging/opencode.jsonc valid JSON"
fi

# TC5: staging Hermes overlay is valid YAML
if python3 -c "import yaml; yaml.safe_load(open('${STAGING_HERMES_OVERLAY}'))" 2>/dev/null; then
    _pass "staging/config-hermes-overlay.yaml valid YAML"
else
    _fail "staging/config-hermes-overlay.yaml valid YAML"
fi

# TC2: opencode.jsonc has provider.opencode + free model (grep-based, no quoting issues)
if grep -q '"apiKey": "{env:OPENCODE_API_KEY}"' "${STAGING_OPENCODE}" 2>/dev/null; then
    _pass "opencode.jsonc has provider.opencode ({env:OPENCODE_API_KEY})"
else
    _fail "opencode.jsonc has provider.opencode ({env:OPENCODE_API_KEY})"
fi
if grep -q '"model": "opencode/deepseek-v4-flash-free"' "${STAGING_OPENCODE}" 2>/dev/null; then
    _pass "opencode.jsonc model = opencode/deepseek-v4-flash-free"
else
    _fail "opencode.jsonc model = opencode/deepseek-v4-flash-free"
fi

# TC3: Hermes overlay custom_providers has >1 model (line-count the models map)
_oc_models=$(grep -c 'context_length' "${STAGING_HERMES_OVERLAY}" 2>/dev/null || echo 0)
if [ "$_oc_models" -gt 1 ] 2>/dev/null; then
    _pass "Hermes overlay custom_providers has ${_oc_models} models"
else
    _fail "Hermes overlay custom_providers has ${_oc_models} models (expected >1)"
fi

# TC8: preserved blocks in opencode.jsonc
for blk in permission plugin agent server; do
    if grep -q "\"${blk}\"" "${STAGING_OPENCODE}" 2>/dev/null; then
        _pass "opencode.jsonc preserves '${blk}' block"
    else
        _fail "opencode.jsonc preserves '${blk}' block"
    fi
done

# DRY-RUN: verify no live files changed
if [ "$DRY_RUN" = true ]; then
    _dc_err=0
    while IFS='=' read -r f expected; do
        [ -z "$f" ] && continue
        if [ -f "$f" ]; then
            _dc_actual=$(sha256sum "$f" | awk '{print $1}')
            if [ "$_dc_actual" != "$expected" ]; then
                echo "!! CHECKSUM MISMATCH: $f was modified!" >&2
                _dc_err=$((_dc_err + 1))
            fi
        fi
    done <<< "$LIVE_CHECKSUMS"
    if [ "$_dc_err" -eq 0 ]; then
        _pass "no live config files modified"
    else
        _fail "${_dc_err} live config file(s) were modified"
    fi
fi

echo
echo "============================================================"
echo " RESULT: ${PASS} passed, ${FAIL} failed"
echo " Staging dir: ${STAGING_DIR}"
echo "============================================================"
if [ -f "${STAGING_DIFF}" ]; then
    echo
    echo "--- OpenCode merge summary ---"
    cat "${STAGING_DIFF}"
fi

[ "$FAIL" -eq 0 ]
