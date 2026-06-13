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
# key_env hardening is documented in README.md as an optional step.

# generate_hermes_overlay — merge live config.yaml custom_providers -> STAGING.
generate_hermes_overlay() {
    mkdir -p "$(dirname "$STAGING_HERMES_OVERLAY")"

    local live_cfg="${CONFIG}"
    local staging="${STAGING_HERMES_OVERLAY}"
    local base_url="${LITELLM_BASE_URL}"
    local default_model="${DEFAULT_MODEL}"
    local models_file="${STAGING_MODELS}"

    # Models are read from $STAGING_MODELS file (avoids stdin/heredoc conflict).
    python3 - \
        "$live_cfg" "$staging" "$base_url" "$default_model" "$models_file" << 'PYEOF'
import sys, yaml

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

# --- Build the merged custom_providers entry (Form B: models map) -----------
models_map = {}
for mid in discovered:
    models_map[mid] = {"context_length": 200000}

new_litellm_entry = {
    "name": "litellm",
    "base_url": base_url,
    "models": models_map,
}
# Carry forward the existing inline key so the overlay is immediately
# functional. (key_env hardening is a documented optional step.)
if existing_api_key:
    new_litellm_entry["api_key"] = existing_api_key

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

# --- Ensure model.default + model.name are set to the default model ---------
model_sec = cfg.setdefault("model", {})
if not isinstance(model_sec, dict):
    model_sec = {}
    cfg["model"] = model_sec
if not model_sec.get("default"):
    model_sec["default"] = default_model
if not model_sec.get("name"):
    model_sec["name"] = default_model

# --- Write staging overlay (valid YAML) --------------------------------------
with open(out_path, "w") as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

# --- Summary -----------------------------------------------------------------
summary_lines = [
    "Hermes config overlay summary",
    "=" * 40,
    "custom_providers.litellm  -> replaced" if replaced else "custom_providers.litellm  -> appended",
    "models listed            -> %d" % len(models_map),
    "api_key                  -> carried from existing config (%s)" % ("present" if existing_api_key else "MISSING"),
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
