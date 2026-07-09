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
#   bash generate.sh                # full run: discover + generate all staging
#   bash generate.sh --dry-run      # same, plus validation assertions + live-file
#                                   # checksum verification (no writes outside staging)
#   bash generate.sh --apply        # generate staging, then copy to live paths (with .bak)
#   bash generate.sh --apply --dry-run  # generate staging, validate, show apply plan
#   bash generate.sh --apply --shell-integration  # apply + source export-env.sh from ~/.bashrc
#   bash generate.sh --apply --remove-shell-integration  # remove the rc-file block
#   bash generate.sh --help         # show this help
#
# Strict requirement: OpenCode defaults to opencode/deepseek-v4-flash-free
# (free Zen model) so Hermes->OpenCode delegation burns no paid quota.

set -euo pipefail

# --- Locate lib/ relative to this script -------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# --- Parse args --------------------------------------------------------------
DRY_RUN=false
APPLY=false
SHELL_INTEGRATION=false
REMOVE_SHELL_INTEGRATION=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --apply) APPLY=true ;;
        --shell-integration) SHELL_INTEGRATION=true ;;
        --remove-shell-integration) REMOVE_SHELL_INTEGRATION=true ;;
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

# --- Validate shell-integration flags ----------------------------------------
if [ "$SHELL_INTEGRATION" = true ] && [ "$REMOVE_SHELL_INTEGRATION" = true ]; then
    echo "--shell-integration and --remove-shell-integration are mutually exclusive." >&2
    exit 1
fi
if [ "$SHELL_INTEGRATION" = true ] && [ "$APPLY" = false ]; then
    echo "--shell-integration requires --apply (use: generate.sh --apply --shell-integration)" >&2
    exit 1
fi
if [ "$REMOVE_SHELL_INTEGRATION" = true ] && [ "$APPLY" = false ]; then
    echo "--remove-shell-integration requires --apply" >&2
    exit 1
fi

# --- Source lib modules ------------------------------------------------------
# shellcheck source=lib/constants.sh
source "${LIB_DIR}/constants.sh"

# --- Source user env vars (model selection, API keys, optional settings) -----
# Sources .env from the script's directory (repo or install location), NOT
# ~/.hermes/.env. The repo's .env is the single source of truth for config
# generation. 2>/dev/null so the script works when .env is absent.
source "${SCRIPT_DIR}/.env" 2>/dev/null || true
# Re-apply OPENAI_BASE_URL default + trailing-slash strip after .env source,
# because an empty OPENAI_BASE_URL= in .env would clobber the constants.sh default.
OPENAI_BASE_URL="${OPENAI_BASE_URL:-http://localhost:4000}"
OPENAI_BASE_URL="${OPENAI_BASE_URL%/}"

# Export OPENAI_API_KEY and OPENAI_BASE_URL too so {env:OPENAI_API_KEY} in
# opencode.jsonc resolves from the subshell environment when opencode runs.
export OPENAI_API_KEY OPENAI_BASE_URL

# Export key variables so Python subprocesses (via os.environ.get) can see them.
# Without explicit export, `source .env` creates shell variables only (the .env
# file uses `KEY=value` not `export KEY=value`), which Python cannot access.
export OPENCODE_DEFAULT_MODEL OPENCODE_SMALL_MODEL OPENCODE_AGENT_MODEL
export OPENCODE_FALLBACK_MODEL OPENAI_DEFAULT_MODEL HERMES_DEFAULT_MODEL
export OPENCODE_COMPRESSION_THRESHOLD
export HERMES_YOLO_MODE HERMES_GOAL_MAX_TURNS HERMES_DELEGATION_MAX_ITERATIONS
export HERMES_DELEGATION_MODEL HERMES_DELEGATION_PROVIDER HERMES_COMPRESSION_THRESHOLD
# shellcheck source=lib/model-discovery.sh
source "${LIB_DIR}/model-discovery.sh"
# shellcheck source=lib/config-opencode.sh
source "${LIB_DIR}/config-opencode.sh"
# shellcheck source=lib/config-hermes.sh
source "${LIB_DIR}/config-hermes.sh"
# shellcheck source=lib/env-auth.sh
source "${LIB_DIR}/env-auth.sh"
# shellcheck source=lib/sync-env.sh
source "${LIB_DIR}/sync-env.sh"

echo "============================================================"
echo " Hermes x OpenCode host config generator"
if [ "$APPLY" = true ] && [ "$DRY_RUN" = true ]; then
    echo " Mode: APPLY-DRY-RUN (staging + validate + show plan)"
elif [ "$APPLY" = true ]; then
    echo " Mode: APPLY (staging + copy to live)"
elif [ "$DRY_RUN" = true ]; then
    echo " Mode: DRY-RUN (staging + validation)"
else
    echo " Mode: GENERATE (staging only)"
fi
echo " OpenAI:   ${OPENAI_BASE_URL}"
echo " OpenCode model: ${OPENCODE_DEFAULT_MODEL}"
echo "============================================================"
echo

# --- DRY-RUN: snapshot live file checksums (prove no mutation) --------------
LIVE_CHECKSUMS=""
snapshot_live_checksums() {
    local files=("${CONFIG}" "${OPENCODE_CONFIG}" "${HERMES_ENV}" "${OPENCODE_AUTH}" "${OPENCODE_DCP_CONFIG}")
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

# --- rc-file detection helper ------------------------------------------------
_detect_rc_file() {
    case "$(basename "$SHELL")" in
        bash) echo "$HOME/.bashrc" ;;
        zsh)  echo "$HOME/.zshrc" ;;
        *)    echo "" ;;
    esac
}

if [ "$DRY_RUN" = true ] && [ "$APPLY" = false ]; then
    snapshot_live_checksums
fi

# --- Clean staging dir -------------------------------------------------------
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# --- Generate export-env.sh (sourceable env export helper) -------------------
# Shell env vars so opencode can resolve {env:OPENAI_API_KEY} references.
# Uses UNQUOTED EXPORT_EOF so values expand at generation time (the shell has
# already sourced .env at this point), baking in real values for the user to
# source in a different shell before running 'opencode run'.
# Use unquoted EXPORT_EOF so values expand at generation time.
# Use ${VAR:-} for optional vars so set -u doesn't abort on unset.
cat > "${STAGING_DIR}/export-env.sh" << EXPORT_EOF
#!/usr/bin/env bash
# Source this file to export env vars needed for opencode delegation.
# Generated by hermes-x-opencode host config generator.
# Usage: source ~/.hermes/host-config-gen/export-env.sh

export OPENAI_API_KEY="${OPENAI_API_KEY:-}"
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-}"
export OPENCODE_DEFAULT_MODEL="${OPENCODE_DEFAULT_MODEL:-}"
export OPENCODE_SMALL_MODEL="${OPENCODE_SMALL_MODEL:-}"
export OPENCODE_AGENT_MODEL="${OPENCODE_AGENT_MODEL:-}"
export OPENCODE_FALLBACK_MODEL="${OPENCODE_FALLBACK_MODEL:-}"
export OPENCODE_ZEN_API_KEY="${OPENCODE_ZEN_API_KEY:-}"
export OPENAI_DEFAULT_MODEL="${OPENAI_DEFAULT_MODEL:-}"
export HERMES_DEFAULT_MODEL="${HERMES_DEFAULT_MODEL:-}"
EXPORT_EOF
chmod 600 "${STAGING_DIR}/export-env.sh"

# --- Phase 1: Model discovery ------------------------------------------------
discover_models
echo

# --- Phase 2: OpenCode config merge (provider.opencode + litellm + models) ---
echo "-- Generating OpenCode staging (MERGE mode)..."
generate_opencode_staging
echo

# --- Phase 2b: DCP (dynamic context pruning) config ------------------------
echo "-- Generating DCP config staging (compress thresholds)..."
generate_dcp_staging
echo

# --- Phase 3: Hermes config overlay (custom_providers models map) -----------
echo "-- Generating Hermes config overlay..."
generate_hermes_overlay
echo

# --- Phase 4: auth.json staging ---------------------------------------------
echo "-- Generating auth.json staging..."
generate_auth_staging "${SCRIPT_DIR}/.env"
echo

# --- Zen API key validation --------------------------------------------------
# shellcheck source=lib/validate-zen.sh
source "${LIB_DIR}/validate-zen.sh"
validate_zen_key || true
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

# TC4b: staging dcp.jsonc is valid JSON and pins a percentage maxContextLimit
if python3 -m json.tool "${STAGING_DCP}" >/dev/null 2>&1; then
    _pass "staging/dcp.jsonc valid JSON"
else
    _fail "staging/dcp.jsonc valid JSON"
fi
if grep -qE '"maxContextLimit": *"[0-9]+%"' "${STAGING_DCP}" 2>/dev/null; then
    _pass "dcp.jsonc compress.maxContextLimit is a percentage of model context"
else
    _fail "dcp.jsonc compress.maxContextLimit is a percentage of model context"
fi

# TC2a: opencode.jsonc has provider.opencode with Zen key (grep-based)
if grep -q '"apiKey": "{env:OPENCODE_ZEN_API_KEY}"' "${STAGING_OPENCODE}" 2>/dev/null; then
    _pass "opencode.jsonc has provider.opencode ({env:OPENCODE_ZEN_API_KEY})"
else
    _fail "opencode.jsonc has provider.opencode ({env:OPENCODE_ZEN_API_KEY})"
fi

# TC2b: opencode.jsonc model field is present and non-empty.
# config-opencode.sh's normalize_model_id() canonicalizes bare ids to
# litellm/<id> or opencode/<id>, so the staging value may differ from the raw
# OPENCODE_DEFAULT_MODEL env var. Read the actual staging value (source of truth)
# instead of re-deriving it from the env (karpathy §6: single source of truth).
_staging_model=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('model',''))" "${STAGING_OPENCODE}" 2>/dev/null || echo "")
if [ -n "$_staging_model" ]; then
    _pass "opencode.jsonc model field present (= ${_staging_model})"
else
    _fail "opencode.jsonc model field missing or empty"
fi

# TC3: Hermes overlay custom_providers has >=1 model (line-count the models map).
# Uses >=1 (not >1) because a legitimate Zen-only setup (no OPENAI creds) falls
# back to [default_model] only, yielding 1 model — that is correct, not a failure.
_oc_models=$(grep -c 'context_length' "${STAGING_HERMES_OVERLAY}" 2>/dev/null || echo 0)
if [ "$_oc_models" -ge 1 ] 2>/dev/null; then
    _pass "Hermes overlay custom_providers has ${_oc_models} models"
else
    _fail "Hermes overlay custom_providers has ${_oc_models} models (expected >=1)"
fi

# TC8: preserved blocks in opencode.jsonc (only check blocks that existed in source)
_preserve_blocks="permission plugin agent"
if [ -f "${OPENCODE_CONFIG}" ]; then
    _extra_blocks=$(python3 -c "
import json, re, sys
try:
    with open(sys.argv[1]) as f:
        text = f.read()
    stripped = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    # String-aware // strip
    result = []; i = 0; in_str = False; esc = False
    while i < len(stripped):
        ch = stripped[i]
        if esc: result.append(ch); esc = False; i += 1; continue
        if in_str:
            result.append(ch)
            if ch == '\\\\': esc = True
            elif ch == '\"': in_str = False
            i += 1; continue
        if ch == '\"': in_str = True; result.append(ch); i += 1; continue
        if ch == '/' and i+1 < len(stripped) and stripped[i+1] == '/':
            while i < len(stripped) and stripped[i] != '\n': i += 1
            continue
        result.append(ch); i += 1
    cfg = json.loads(''.join(result))
    for k in ('server', 'experimental'):
        if k in cfg: print(k)
except: pass
" "${OPENCODE_CONFIG}" 2>/dev/null || true)
    _preserve_blocks="${_preserve_blocks} ${_extra_blocks}"
fi
for blk in $_preserve_blocks; do
    if grep -q "\"${blk}\"" "${STAGING_OPENCODE}" 2>/dev/null; then
        _pass "opencode.jsonc preserves '${blk}' block"
    else
        _fail "opencode.jsonc preserves '${blk}' block"
    fi
done

# DRY-RUN: verify no live files changed (skip when --apply, since apply modifies live files)
if [ "$DRY_RUN" = true ] && [ "$APPLY" = false ]; then
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

# --- Apply: copy staging → live (with backups) ------------------------------
if [ "$APPLY" = true ]; then
    echo ""
    echo "============================================================"
    echo " APPLY"
    echo "============================================================"

    # Define staging→live mapping as parallel arrays
    _staging_sources=("${STAGING_OPENCODE}" "${STAGING_HERMES_OVERLAY}" "${STAGING_AUTH}" "${STAGING_DIR}/export-env.sh" "${STAGING_DCP}")
    _live_dests=("${OPENCODE_CONFIG}" "${CONFIG}" "${OPENCODE_AUTH}" "${GEN_DIR}/export-env.sh" "${OPENCODE_DCP_CONFIG}")
    _apply_labels=("OpenCode config" "Hermes overlay" "OpenCode auth" "Shell env export helper" "DCP config")

    if [ "$DRY_RUN" = true ]; then
        # --- DRY-RUN mode: validate staging files and report plan ---
        echo ""
        echo ">> Apply dry-run: validating staging files and showing plan..."
        echo ""
        _apply_fail=0
        for i in "${!_staging_sources[@]}"; do
            src="${_staging_sources[$i]}"
            dst="${_live_dests[$i]}"
            label="${_apply_labels[$i]}"

            if [ ! -f "$src" ]; then
                echo "  [SKIP] $label: staging file not found ($src)"
                _apply_fail=1
                continue
            fi

            # Validate format
            case "$src" in
                *.jsonc|*.json)
                    if python3 -m json.tool "$src" >/dev/null 2>&1; then
                        echo "  [OK] $label: valid JSON ($(wc -c < "$src") bytes)"
                    else
                        echo "  [ERR] $label: invalid JSON ($src)"
                        _apply_fail=1
                    fi
                    ;;
                *.yaml|*.yml)
                    if python3 -c "import yaml; yaml.safe_load(open('$src'))" 2>/dev/null; then
                        echo "  [OK] $label: valid YAML ($(wc -c < "$src") bytes)"
                    else
                        echo "  [ERR] $label: invalid YAML ($src)"
                        _apply_fail=1
                    fi
                    ;;
            esac

            # Show what would happen
            if [ -f "$dst" ]; then
                echo "  -> Would backup: $dst → ${dst}.bak"
            fi
            echo "  -> Would apply: $src → $dst"
        done
        if [ "$_apply_fail" -eq 1 ]; then
            echo ""
            echo "!! APPLY DRY-RUN FAILED: fix issues above before running --apply" >&2
            FAIL=$((FAIL + 1))
        else
            echo ""
            echo ">> Apply dry-run passed: all staging files valid"
        fi

        # --- Shell integration dry-run plan ---
        if [ "$SHELL_INTEGRATION" = true ]; then
            _rc="$(_detect_rc_file)"
            if [ -z "$_rc" ]; then
                echo "  [ERR] Unsupported shell: $SHELL (only bash and zsh are supported)" >&2
                FAIL=$((FAIL + 1))
            elif [ -f "$_rc" ] && grep -qF '# >>> hermes host-config-gen env bridge (managed, do not edit) >>>' "$_rc" 2>/dev/null; then
                echo "  [OK] Shell integration already present in $_rc"
            else
                echo "  -> Would add shell integration to $_rc"
            fi
        elif [ "$REMOVE_SHELL_INTEGRATION" = true ]; then
            _rc="$(_detect_rc_file)"
            if [ -z "$_rc" ]; then
                echo "  [ERR] Unsupported shell: $SHELL (only bash and zsh are supported)" >&2
                FAIL=$((FAIL + 1))
            elif [ -f "$_rc" ] && grep -qF '# >>> hermes host-config-gen env bridge (managed, do not edit) >>>' "$_rc" 2>/dev/null; then
                echo "  -> Would remove shell integration from $_rc"
            else
                echo "  [OK] No shell integration block found in $_rc"
            fi
        fi
    else
        # --- REAL apply: copy with backups ---
        for i in "${!_staging_sources[@]}"; do
            src="${_staging_sources[$i]}"
            dst="${_live_dests[$i]}"
            label="${_apply_labels[$i]}"

            if [ ! -f "$src" ]; then
                echo "  [SKIP] $label: staging file not found ($src)"
                continue
            fi

            # Backup existing live file
            if [ -f "$dst" ]; then
                cp "$dst" "${dst}.bak"
                echo "  Backed up: $dst → ${dst}.bak"
            fi

            # Ensure destination directory exists
            mkdir -p "$(dirname "$dst")"

            # Copy staging → live
            cp "$src" "$dst"
            echo "  Applied: $src → $dst"
        done

        # --- Shell integration: add guarded source block to rc file ---
        if [ "$SHELL_INTEGRATION" = true ]; then
            _rc="$(_detect_rc_file)"
            if [ -z "$_rc" ]; then
                echo "  [ERR] Unsupported shell: $SHELL (only bash and zsh are supported)" >&2
                FAIL=$((FAIL + 1))
            elif [ -f "$_rc" ] && grep -qF '# >>> hermes host-config-gen env bridge (managed, do not edit) >>>' "$_rc" 2>/dev/null; then
                echo "  [OK] Shell integration already present in $_rc"
            else
                {
                    echo ""
                    echo "# >>> hermes host-config-gen env bridge (managed, do not edit) >>>"
                    echo "[ -f \"\$HOME/.hermes/host-config-gen/export-env.sh\" ] && source \"\$HOME/.hermes/host-config-gen/export-env.sh\""
                    echo "# <<< hermes host-config-gen env bridge <<<"
                } >> "$_rc"
                echo "  Added shell integration to $_rc"
            fi
        fi

        # --- Shell integration: remove guarded block from rc file ---
        if [ "$REMOVE_SHELL_INTEGRATION" = true ]; then
            _rc="$(_detect_rc_file)"
            if [ -z "$_rc" ]; then
                echo "  [ERR] Unsupported shell: $SHELL (only bash and zsh are supported)" >&2
                FAIL=$((FAIL + 1))
            elif [ -f "$_rc" ] && grep -qF '# >>> hermes host-config-gen env bridge (managed, do not edit) >>>' "$_rc" 2>/dev/null; then
                sed -i '/^# >>> hermes host-config-gen env bridge (managed, do not edit) >>>/,/^# <<< hermes host-config-gen env bridge <<<$/d' "$_rc"
                echo "  Removed shell integration from $_rc"
            else
                echo "  [OK] No shell integration block found in $_rc"
            fi
        fi
        # --- Sync managed .env section to ~/.hermes/.env ---
        # shellcheck source=lib/sync-env.sh
        sync_env_to_hermes "${SCRIPT_DIR}/.env" || true
    fi
fi

echo
echo "============================================================"
echo " RESULT: ${PASS} passed, ${FAIL} failed"
echo " Staging dir: ${STAGING_DIR}"
echo "============================================================"

[ "$FAIL" -eq 0 ]
