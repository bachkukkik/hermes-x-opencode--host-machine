# lib/validate-zen.sh — validate OPENCODE_ZEN_API_KEY against Zen API (host version)
#
# Adapted from the Docker stack's validate-opencode.sh for host use.
# Non-fatal: always returns 0, logs warnings on failure.

validate_zen_key() {
    local key="${OPENCODE_ZEN_API_KEY:-}"
    if [ -z "$key" ]; then
        echo "== OPENCODE_ZEN_API_KEY not set — opencode/ free models use public fallback (may be limited)"
        return 0
    fi

    local response
    response=$(curl -sf --max-time 10 \
        -H "Authorization: Bearer ${key}" \
        "https://opencode.ai/zen/v1/models" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        echo "!! WARNING: OPENCODE_ZEN_API_KEY is set but the Zen API returned an error."
        echo "   opencode/ models may fail with 401 Invalid API key."
        echo "   Get a valid key at: https://opencode.ai/auth"
        return 0
    fi

    local model_count
    model_count=$(echo "$response" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(len(d.get('data', [])))
except Exception:
    print(0)
" 2>/dev/null || echo "0")

    echo "== OPENCODE_ZEN_API_KEY validated — Zen API returned ${model_count} models"
    return 0
}
