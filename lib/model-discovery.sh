# lib/model-discovery.sh — LiteLLM proxy model discovery (host adaptation)
#
# Ports the Docker reference discovery + filter pipeline. CRITICAL (EC2): the
# LiteLLM API key is read from ~/.hermes/config.yaml IN-PROCESS via python3 and
# the HTTP request is performed inside the SAME python process — the secret
# never round-trips through a shell variable (Hermes secret-redaction mangles
# keys interpolated into the agent shell).
#
# Output: sets the global DISCOVERED_MODELS (newline-separated model ids).

# discover_models — populate $DISCOVERED_MODELS from LiteLLM /v1/models.
discover_models() {
    local default_model="${DEFAULT_MODEL:-zai/glm-5.1}"
    local config_path="${CONFIG}"
    local base_url="${LITELLM_BASE_URL}"
    DISCOVERED_MODELS=""

    echo "== Discovering models from ${base_url}/v1/models ..."

    # Everything (key read + HTTP + filter) happens inside one python process
    # so the api_key is never exposed as a shell variable.
    local result
    result=$(python3 - "$config_path" "$base_url" "$default_model" << 'PYEOF'
import sys, json, re, urllib.request

config_path, base_url, default_model = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    import yaml
except Exception:
    yaml = None

# --- Read the LiteLLM api_key from config.yaml IN-PROCESS (never grep|sed) --
api_key = ""
try:
    with open(config_path) as f:
        raw = f.read()
    if yaml:
        data = yaml.safe_load(raw) or {}
        m = data.get("model") or {}
        if isinstance(m, dict) and isinstance(m.get("api_key"), str):
            api_key = m["api_key"].strip()
        # Fallback: custom_providers[].api_key
        if not api_key:
            for cp in (data.get("custom_providers") or []):
                if isinstance(cp, dict) and isinstance(cp.get("api_key"), str) \
                        and cp["api_key"].strip():
                    api_key = cp["api_key"].strip()
                    break
except Exception:
    pass

# --- Query LiteLLM /v1/models ------------------------------------------------
ids = []
if api_key:
    url = base_url.rstrip("/") + "/v1/models"
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + api_key})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.load(resp)
        for m in data.get("data", []):
            mid = m.get("id", "")
            if mid:
                ids.append(mid)
    except Exception:
        pass  # EC1: leave ids empty -> fallback below

# --- Filter pipeline (identical to Docker reference) -------------------------
skip_patterns = [
    r'embed', r'whisper', r'tts', r'dall[\-\-]?e', r'sora',
    r'\bimage\b', r'realtime', r'transcrib', r'moderat', r'\baudio\b',
    r'codegen', r'babbage', r'davinci', r'\bcurie\b', r'\bada\b',
    r'text-', r'stable', r'midjourney', r'flux', r'/sd/', r'\bmj\b',
    r'replicate', r'resolution', r'cli-proxy-api',
]
skip_re = [re.compile(p, re.IGNORECASE) for p in skip_patterns]

seen = set()
filtered = []
for mid in ids:
    if any(p.search(mid) for p in skip_re):
        continue
    if re.search(r'/\*$', mid):           # drop wildcard ids like "anthropic/*"
        continue
    key = mid.lower()                      # dedupe case-insensitively
    if key in seen:
        continue
    seen.add(key)
    filtered.append(mid)

if not filtered:
    filtered = [default_model]
elif not any(m.lower() == default_model.lower() for m in filtered):
    filtered.insert(0, default_model)

sys.stdout.write("\n".join(filtered))
PYEOF
    ) 2>/dev/null || true

    if [ -z "$result" ]; then
        echo "!! LiteLLM unreachable or empty — falling back to default model only (EC1)."
        result="$default_model"
    fi

    DISCOVERED_MODELS="$result"
    local count
    count=$(printf '%s\n' "$DISCOVERED_MODELS" | grep -c .)
    echo "== Discovered ${count} chat models."

    # Write to a file so downstream generators can read it as an arg
    # (avoids the stdin/heredoc conflict — python3 - reads its script from
    # stdin via the heredoc, so sys.stdin can't also receive piped data).
    mkdir -p "$(dirname "${STAGING_MODELS:-/dev/null}")"
    printf '%s\n' "$DISCOVERED_MODELS" > "${STAGING_MODELS}"
}
