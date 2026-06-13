# lib/env-auth.sh — environment variable resolution + auth.json staging
#
# Resolves credentials for the dual-provider setup:
#   - opencode (Zen free models): OPENCODE_ZEN_API_KEY from ~/.hermes/.env
#   - litellm (proxy):            api_key from ~/.hermes/config.yaml
#
# Produces a STAGING auth.json (~/.local/share/opencode/auth.json format) that
# the orchestrator can review/apply. NEVER overwrites the live auth.json or
# .env directly. All key reads happen IN-PROCESS via python (EC2).

# generate_auth_staging — read keys in-process, write staging auth.json.
generate_auth_staging() {
    mkdir -p "$(dirname "$STAGING_AUTH")"

    local env_file="${HERMES_ENV}"
    local config_file="${CONFIG}"
    local staging="${STAGING_AUTH}"

    python3 - "$env_file" "$config_file" "$staging" << 'PYEOF'
import sys, os, re, json, yaml

env_path, config_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

# --- Read OPENCODE_ZEN_API_KEY from .env (EC2: in-process, never shell var) --
def read_env_file(path):
    vals = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                m = re.match(r'^([A-Z_][A-Z0-9_]*)=(.*)$', line)
                if m:
                    v = m.group(2).strip().strip('"').strip("'")
                    vals[m.group(1)] = v
    except FileNotFoundError:
        pass
    return vals

env_vals = read_env_file(env_path)
zen_key = env_vals.get("OPENCODE_ZEN_API_KEY", "")
openai_key = env_vals.get("OPENAI_API_KEY", "")

# --- Read litellm key from config.yaml as fallback for OPENAI_API_KEY --------
if not openai_key:
    try:
        with open(config_path) as f:
            cfg = yaml.safe_load(f) or {}
        m = cfg.get("model") or {}
        if isinstance(m, dict) and isinstance(m.get("api_key"), str):
            openai_key = m["api_key"].strip()
        if not openai_key:
            for cp in (cfg.get("custom_providers") or []):
                if isinstance(cp, dict) and isinstance(cp.get("api_key"), str) \
                        and cp["api_key"].strip():
                    openai_key = cp["api_key"].strip()
                    break
    except Exception:
        pass

# --- Build staging auth.json (OpenCode credential store format) --------------
# OpenCode auth.json stores per-provider API keys. The {env:VAR} refs in
# opencode.jsonc resolve at runtime, but auth.json is a FALLBACK credential
# store (Docker pattern: seed both providers as belt-and-suspenders).
auth = {}
if zen_key:
    auth["opencode"] = {"apiKey": zen_key}
if openai_key:
    auth["litellm"] = {"apiKey": openai_key}

with open(out_path, "w") as f:
    json.dump(auth, f, indent=2)
    f.write("\n")

# --- Summary + guidance ------------------------------------------------------
lines = [
    "auth.json staging summary",
    "=" * 40,
    "OPENCODE_ZEN_API_KEY  -> %s" % ("found in .env (opencode provider seeded)" if zen_key else "NOT FOUND in .env"),
    "OPENAI_API_KEY        -> %s" % ("found (litellm provider seeded)" if openai_key else "resolved from config.yaml (litellm provider seeded)" if openai_key else "NOT FOUND"),
    "",
    "ACTION REQUIRED for opencode/deepseek-v4-flash-free (free Zen model):",
    "  The opencode provider block uses {env:OPENCODE_API_KEY}. You must",
    "  export OPENCODE_API_KEY in your environment or add it to ~/.hermes/.env:",
    "    echo 'OPENCODE_API_KEY=<your-zen-key>' >> ~/.hermes/.env",
    "  (Both keys must have the SAME value — OPENCODE_ZEN_API_KEY is the",
    "   OpenCode Zen credential, and OPENCODE_API_KEY is what opencode.jsonc",
    "   references via {env:OPENCODE_API_KEY}.)",
    "",
    "Staging auth.json written to: %s" % out_path,
]
print("\n".join(lines))
PYEOF
}
