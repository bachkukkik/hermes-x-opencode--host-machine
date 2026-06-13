#!/usr/bin/env bash
# install.sh — deploy the host-config generator to ~/.hermes/host-config-gen/
#
# Usage:
#   bash install.sh             # install + dry-run validate
#   bash install.sh --no-run    # install only, don't run generator
#
# Prerequisites: bash, python3, python3-yaml, hermes, opencode (optional),
# and a reachable LiteLLM proxy at http://localhost:4000 (or LITELLM_BASE_URL).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${HOME}/.hermes/host-config-gen"
RUN_GENERATOR=true

for arg in "$@"; do
    case "$arg" in
        --no-run) RUN_GENERATOR=false ;;
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

echo "== Installing host-config generator to ${DEST} ..."

# --- Prerequisite checks -----------------------------------------------------
echo "== Checking prerequisites ..."

check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "  [ok] $1 found"
        return 0
    else
        echo "  [MISSING] $1 not found"
        return 1
    fi
}

MISSING=0
check_cmd bash       || MISSING=1
check_cmd python3    || MISSING=1

# python3 yaml module
if python3 -c "import yaml" 2>/dev/null; then
    echo "  [ok] python3 yaml module"
else
    echo "  [MISSING] python3 yaml module — install with: pip install pyyaml"
    MISSING=1
fi

# hermes (optional but expected)
if command -v hermes >/dev/null 2>&1; then
    echo "  [ok] hermes found"
else
    echo "  [warn] hermes not found (config generation will still work, but apply step requires it)"
fi

# opencode (optional but expected for interop)
if command -v opencode >/dev/null 2>&1; then
    echo "  [ok] opencode found"
else
    echo "  [warn] opencode not found (interop test will be skipped)"
fi

if [ "$MISSING" -ne 0 ]; then
    echo "!! Missing required prerequisites. Aborting." >&2
    exit 1
fi

# --- Deploy ------------------------------------------------------------------
mkdir -p "${DEST}/lib"

cp "${SCRIPT_DIR}/generate.sh" "${DEST}/"
cp "${SCRIPT_DIR}/README.md"   "${DEST}/"
cp "${SCRIPT_DIR}/lib/"*.sh    "${DEST}/lib/"

chmod +x "${DEST}/generate.sh"

echo "== Deployed files:"
find "${DEST}" -type f -name '*.sh' -o -name '*.md' | sort

# --- Verify deployment -------------------------------------------------------
echo "== Verifying deployment ..."
for script in "${DEST}/generate.sh" "${DEST}/lib/"*.sh; do
    if bash -n "$script" 2>/dev/null; then
        echo "  [ok] bash -n $(basename "$script")"
    else
        echo "  [FAIL] bash -n $(basename "$script")" >&2
        exit 1
    fi
done

# --- Optionally run generator ------------------------------------------------
if [ "$RUN_GENERATOR" = true ]; then
    echo
    echo "== Running generator (dry-run) ..."
    bash "${DEST}/generate.sh" --dry-run || {
        echo "!! Generator dry-run failed. Review the output above." >&2
        exit 1
    }
    echo
    echo "== Dry-run passed. Review staging output at:"
    echo "   ${DEST}/staging/"
    echo
    echo "== To apply the staging configs to your live system, see:"
    echo "   ${DEST}/README.md (section: Applying the staging output)"
fi

echo
echo "== Installation complete."
