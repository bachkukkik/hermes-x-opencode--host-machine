# lib/config-hermes.sh — Hermes config.yaml overlay generator (host)
#
# Produces a STAGING overlay that the orchestrator can review/apply later.
# NEVER overwrites the live ~/.hermes/config.yaml (applied in the integration
# step, T3).
#
# Schema finding: Hermes custom_providers supports TWO forms:
#   Form A (scalar): { name, base_url, api_key, model }  — host's current form
#   Form B (map):    { name, base_url, models: {<id>: {context_length: N}}, key_env: VAR }
#                    — Docker reference form, statically lists all discovered
#                      models so Hermes doesn't need to probe the endpoint.
# We emit Form B (the Docker "copycat" form). The existing inline api_key is
# read in-process and carried forward so the overlay is functional on apply;
# key_env hardening automatically falls back to OPENAI_API_KEY when no inline api_key exists.

# Resolve a model's context length from a small pin table of well-known model
# families (substring match, longest/most-specific pattern first). Echoes the
# pinned value, or empty string when the model is unknown — the caller then
# omits the context_length line so the hermes-agent self-resolves it at runtime
# via its own DEFAULT_CONTEXT_LENGTHS table / models.dev / endpoint probe.
#
# Why pin at all when the agent self-resolves? (1) The DEFAULT model must always
# carry an explicit context_length (see generate_hermes_overlay) so the overlay
# has >=1 entry and the active model gets a sane window, and (2) a few families
# need a defensive correct value — notably glm-5.2, whose true 1M window the
# agent's "glm" catch-all misreports as 202752. Values mirror the agent's
# authoritative DEFAULT_CONTEXT_LENGTHS table (agent/model_metadata.py) so a
# pinned model gets the same value it would self-resolve to.
resolve_ctx_len() {
    local model="$1"
    local m
    m=$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')
    # Longest/most-specific patterns FIRST (first match wins).
    case "$m" in
        *glm-5.2*)           echo 1048576 ;;  # agent catch-all gives 202752 (wrong)
        *claude-opus-4*)     echo 1000000 ;;
        *claude-sonnet-4.6*) echo 1000000 ;;
        *gpt-5.4*)           echo 1050000 ;;
        *gpt-5*)             echo 400000  ;;
        *gpt-4o*)            echo 128000  ;;
        *gpt-4.1*)           echo 1047576 ;;
        *gpt-4*)             echo 128000  ;;
        *gemini*)            echo 1048576 ;;
        *deepseek-v4*)       echo 1000000 ;;
        *minimax-m3*)        echo 1000000 ;;
        *qwen3.6-27b*q4*)    echo 262144  ;;  # quantized GGUF: 262144 real ctx, not family 1M
        *qwen3.6*)           echo 1048576 ;;
        *)                   echo ""      ;;  # unknown -> omit, agent self-resolves
    esac
}

# generate_hermes_overlay — merge live config.yaml custom_providers -> STAGING.
generate_hermes_overlay() {
    mkdir -p "$(dirname "$STAGING_HERMES_OVERLAY")"

    local live_cfg="${CONFIG}"
    local staging="${STAGING_HERMES_OVERLAY}"
    local base_url="${OPENAI_BASE_URL}"
    local default_model="${OPENAI_DEFAULT_MODEL}"
    local models_file="${STAGING_MODELS}"

    # Models are read from $STAGING_MODELS file (avoids stdin/heredoc conflict).
    python3 - \
        "$live_cfg" "$staging" "$base_url" "$default_model" "$models_file" << 'PYEOF'
import sys, yaml, os

live_path, out_path, base_url, default_model, models_file = (
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5],
)

# --- Load live config (source of truth for everything we DON'T touch) -------
try:
    with open(live_path) as f:
        cfg = yaml.safe_load(f) or {}
except FileNotFoundError:
    cfg = {}
except Exception as e:
    sys.stderr.write("!! Could not parse live config.yaml (%s); using empty.\n" % e)
    cfg = {}

if not isinstance(cfg, dict):
    cfg = {}

# --- Read the existing api_key in-process (EC2: never via grep|sed) ----------
existing_api_key = ""
existing_cps = cfg.get("custom_providers") or []
if isinstance(existing_cps, list):
    for cp in existing_cps:
        if isinstance(cp, dict) and isinstance(cp.get("api_key"), str) \
                and cp["api_key"].strip():
            existing_api_key = cp["api_key"].strip()
            break
if not existing_api_key:
    m = cfg.get("model") or {}
    if isinstance(m, dict) and isinstance(m.get("api_key"), str):
        existing_api_key = m["api_key"].strip()

# --- Read discovered models from file ---------------------------------------
discovered = []
try:
    with open(models_file) as f:
        for line in f:
            mid = line.strip()
            if mid:
                discovered.append(mid)
except (FileNotFoundError, TypeError):
    pass

# --- Python equivalent of resolve_ctx_len() for in-heredoc use -------------
def resolve_ctx_len(model_id):
    """Pin table of well-known model families (substring, most-specific first).
    Returns int or None (None = unknown, agent self-resolves)."""
    m = model_id.lower()
    if 'glm-5.2' in m:
        return 1048576      # agent catch-all gives 202752 (wrong)
    if 'claude-opus-4' in m:
        return 1000000
    if 'claude-sonnet-4.6' in m:
        return 1000000
    if 'gpt-5.4' in m:
        return 1050000
    if 'gpt-5' in m:
        return 400000
    if 'gpt-4o' in m:
        return 128000
    if 'gpt-4.1' in m:
        return 1047576
    if 'gpt-4' in m:
        return 128000
    if 'gemini' in m:
        return 1048576
    if 'deepseek-v4' in m:
        return 1000000
    if 'minimax-m3' in m:
        return 1000000
    if 'qwen3.6-27b' in m and 'q4' in m:
        return 262144       # quantized GGUF: 262144 real ctx, not family 1M
    if 'qwen3.6' in m:
        return 1048576
    return None             # unknown -> omit, agent self-resolves

# --- Build the merged custom_providers entry (Form B: models map) -----------
models_map = {}
for mid in discovered:
    ctx_len = resolve_ctx_len(mid)
    if ctx_len is not None:
        # Known family -> pin the accurate context length.
        models_map[mid] = {"context_length": ctx_len}
    elif mid == default_model:
        # Default model ALWAYS gets an explicit context_length so the overlay
        # has >=1 entry and the active model has a sane window.
        models_map[mid] = {"context_length": 200000}
    else:
        # Unknown family -> emit empty mapping so hermes-agent self-resolves
        # context length at runtime (its own table / models.dev / endpoint probe).
        models_map[mid] = {}

new_litellm_entry = {
    "name": "litellm",
    "base_url": base_url,
    "models": models_map,
}
# Carry forward the existing inline key so the overlay is immediately
# functional, or fall back to reading OPENAI_API_KEY from the environment.
if existing_api_key:
    new_litellm_entry["api_key"] = existing_api_key
else:
    new_litellm_entry["key_env"] = "OPENAI_API_KEY"

# Merge into the existing custom_providers list: replace any entry named
# "litellm", otherwise append. Preserve all OTHER custom provider entries.
merged_cps = []
replaced = False
for cp in (cfg.get("custom_providers") or []):
    if isinstance(cp, dict) and cp.get("name") == "litellm":
        merged_cps.append(new_litellm_entry)
        replaced = True
    else:
        merged_cps.append(cp)
if not replaced:
    merged_cps.append(new_litellm_entry)
cfg["custom_providers"] = merged_cps

# Point provider at the generated litellm custom provider so Hermes
# actually uses the custom_providers block we just built.
cfg["provider"] = "custom:litellm"

# --- Ensure model.default + model.name are set to the default model ---------
model_sec = cfg.setdefault("model", {})
if not isinstance(model_sec, dict):
    model_sec = {}
    cfg["model"] = model_sec
# Allow HERMES_DEFAULT_MODEL to override the default model
hermes_default = os.environ.get("HERMES_DEFAULT_MODEL", "").strip()
if hermes_default:
    model_sec["default"] = hermes_default
    model_sec["name"] = hermes_default
else:
    # Always set both fields to default_model — never preserve stale values
    # from the live config, which would cause model.default and model.name
    # to diverge (e.g. "deepseek/deepseek-v4-pro" vs "zai/glm-5.2").
    model_sec["default"] = default_model
    model_sec["name"] = default_model

# --- Optional config blocks (env-gated) --------------------------------------
# approvals.mode: off  (when HERMES_YOLO_MODE=1)
if os.environ.get("HERMES_YOLO_MODE") == "1":
    cfg["approvals"] = {"mode": "off"}

# goals.max_turns  (default 50)
goal_max_turns = int(os.environ.get("HERMES_GOAL_MAX_TURNS", "50"))
cfg["goals"] = {"max_turns": goal_max_turns}

# delegation.max_iterations  (default 50)
deleg_max_iter = int(os.environ.get("HERMES_DELEGATION_MAX_ITERATIONS", "50"))
cfg["delegation"] = {"max_iterations": deleg_max_iter}

# delegation.model  (when HERMES_DELEGATION_MODEL is set)
_delegation_model = os.environ.get("HERMES_DELEGATION_MODEL", "").strip()
if _delegation_model:
    cfg["delegation"]["model"] = _delegation_model

# delegation.provider  (when HERMES_DELEGATION_PROVIDER is set)
_delegation_provider = os.environ.get("HERMES_DELEGATION_PROVIDER", "").strip()
if _delegation_provider:
    cfg["delegation"]["provider"] = _delegation_provider

# context_compression.threshold  (when HERMES_COMPRESSION_THRESHOLD is set)
_compression_threshold = os.environ.get("HERMES_COMPRESSION_THRESHOLD", "").strip()
if _compression_threshold:
    try:
        cfg.setdefault("context_compression", {})["threshold"] = float(_compression_threshold)
    except ValueError:
        pass

# skills.external_dirs  (if optional-skills dir exists)
_optional_skills_dir = os.path.expanduser("~/.hermes/hermes-agent/optional-skills")
if os.path.isdir(_optional_skills_dir):
    skills_sec = cfg.setdefault("skills", {})
    if not isinstance(skills_sec, dict):
        skills_sec = {}
        cfg["skills"] = skills_sec
    ext_dirs = skills_sec.setdefault("external_dirs", [])
    if not isinstance(ext_dirs, list):
        ext_dirs = []
        skills_sec["external_dirs"] = ext_dirs
    if _optional_skills_dir not in ext_dirs:
        ext_dirs.append(_optional_skills_dir)

# --- Write staging overlay (valid YAML) --------------------------------------
with open(out_path, "w") as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

# --- Summary -----------------------------------------------------------------
summary_lines = [
    "Hermes config overlay summary",
    "=" * 40,
    "custom_providers.litellm  -> replaced" if replaced else "custom_providers.litellm  -> appended",
    "models listed            -> %d" % len(models_map),
    "api_key                  -> carried from existing config (%s)" % ("present" if existing_api_key else "key_env: OPENAI_API_KEY"),
    "model.default            -> %s" % model_sec.get("default"),
    "model.name               -> %s" % model_sec.get("name"),
    "other custom_providers   -> %d preserved" % (len(merged_cps) - 1),
    "",
    "NOTE: This is a STAGING overlay. Other config sections (agent, tools,",
    "platforms, etc.) are carried forward unchanged from the live config.",
]
summary = "\n".join(summary_lines)
print(summary)
PYEOF
}
