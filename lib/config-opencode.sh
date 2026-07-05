# lib/config-opencode.sh — OpenCode opencode.jsonc MERGE generator (host)
#
# THE MOST IMPORTANT REQUIREMENT (REQ 4 / EC5): the existing
# ~/.config/opencode/opencode.jsonc has hand-tuned content that MUST be
# preserved (permission deny-list, plugin array, agent build/plan blocks EXCEPT
# their model fields which are overridden to the free Zen model, server block,
# experimental, existing provider.litellm.models map). We never
# overwrite the live file — we deep-merge ONLY the target keys and write the
# result to STAGING_DIR for the orchestrator to review/apply later.
#
# Merge policy:
#   (a) ensure provider.opencode with options.apiKey == "{env:OPENCODE_ZEN_API_KEY}"
#   (b) set top-level "model" + "small_model" to the FREE Zen model;
#       also set agent.build.model and agent.plan.model to the FREE Zen model
#       (other agent sub-block fields like mode/description are preserved)
#   (c) provider.litellm.options.apiKey  -> "{env:OPENAI_API_KEY}"
#       provider.litellm.options.baseURL -> resolved OPENAI_BASE_URL
#   (d) union-merge provider.litellm.models with $DISCOVERED_MODELS
#       (existing hand-tuned limits are PRESERVED; newly discovered models are
#        added with computed get_limits() heuristics — surgical, lossless)
#   (e) create provider.llama_cpp with @ai-sdk/openai-compatible npm, same
#       credentials/baseURL as litellm, and a separate models map for
#       llama_cpp/* models (without this, OpenCode throws ProviderModelNotFoundError)
#   (f) everything else untouched
#
# PROVIDER PREFIX ROUTING (single source of truth):
# All provider prefix logic lives inside the PYEOF Python block:
#   - PROVIDER_PREFIXES constant defines recognized prefixes
#   - normalize_model_id() handles ALL model field routing
#   - PROVIDER_BLOCKS data structure drives provider block generation
# Adding a new provider: add its prefix to PROVIDER_PREFIXES + its block
# config to PROVIDER_BLOCKS. No bash-side changes.
#
# get_limits heuristics (ported verbatim from Docker config-opencode.sh).
_oc_get_limits() { :; }  # implemented in python below for fidelity

# generate_opencode_staging — merge live opencode.jsonc -> STAGING_OPENCODE.
# Args: none. Reads $DISCOVERED_MODELS from stdin (newline-separated).
generate_opencode_staging() {
    mkdir -p "$(dirname "$STAGING_OPENCODE")"

    local live_cfg="${OPENCODE_CONFIG}"
    local staging="${STAGING_OPENCODE}"
    # RAW env values — Python normalizes them via normalize_model_id()
    local default_model="${OPENCODE_DEFAULT_MODEL:-deepseek-v4-flash-free}"
    local small_model="${OPENCODE_SMALL_MODEL:-${OPENCODE_DEFAULT_MODEL:-deepseek-v4-flash-free}}"
    local agent_model="${OPENCODE_AGENT_MODEL:-${OPENCODE_DEFAULT_MODEL:-deepseek-v4-flash-free}}"
    local base_url="${OPENAI_BASE_URL}"
    local diff_file="${STAGING_DIFF}"
    local models_file="${STAGING_MODELS}"

    python3 - \
        "$live_cfg" "$staging" "$default_model" "$base_url" "$diff_file" \
        "$models_file" "$small_model" "$agent_model" << 'PYEOF'
import sys, json, re, os

live_path, out_path, default_model, base_url, diff_path, models_file, small_model, agent_model = (
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5],
    sys.argv[6], sys.argv[7], sys.argv[8],
)

# --- Single source of truth for provider routing ---------------------------
PROVIDER_PREFIXES = ("opencode/", "litellm/", "llama_cpp/")

def normalize_model_id(mid):
    """Return canonical 'provider/model' form.
    Explicit recognized prefixes pass through unchanged.
    Bare ids get litellm/ if OPENAI creds present, else opencode/."""
    for pfx in PROVIDER_PREFIXES:
        if mid.startswith(pfx):
            return mid
    if os.environ.get("OPENAI_BASE_URL") and os.environ.get("OPENAI_API_KEY"):
        return "litellm/" + mid
    return "opencode/" + mid

# --- Provider block config (data-driven) -----------------------------------
# Each entry describes how to generate a provider block in opencode.jsonc.
#   options:     dict of options to set (merged into existing)
#   npm:         optional npm package name
#   filter:      optional function selecting which discovered models go into
#                the provider's models map (absent = no models map)
#   strip_prefix: optional prefix to strip when keying models map entries
PROVIDER_BLOCKS = {
    "opencode": {
        "options": {"apiKey": "{env:OPENCODE_ZEN_API_KEY}"},
    },
    "litellm": {
        "npm": "@ai-sdk/openai-compatible",
        "options": {
            "apiKey": "{env:OPENAI_API_KEY}",
            "baseURL": base_url,
        },
        # ALL discovered models go into litellm's models map
        "filter": lambda mid: True,
    },
    "llama_cpp": {
        "npm": "@ai-sdk/openai-compatible",
        "options": {
            "apiKey": "{env:OPENAI_API_KEY}",
            "baseURL": base_url,
            "timeout": 600000,
            "setCacheKey": True,
        },
        # Only llama_cpp/* discovered models go into this map
        "filter": lambda mid: mid.startswith("llama_cpp/"),
        "strip_prefix": "llama_cpp/",
    },
}

# --- Tolerant JSONC input parser -------------------------------------------
# String-aware: walks char-by-char so // inside quoted strings (e.g. https://)
# are preserved, while real comments are stripped.
def _strip_jsonc_comments(text):
    result = []
    i = 0
    in_string = False
    escape = False
    while i < len(text):
        ch = text[i]
        if escape:
            result.append(ch)
            escape = False
            i += 1
            continue
        if in_string:
            result.append(ch)
            if ch == '\\':
                escape = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        # Outside of a string
        if ch == '"':
            in_string = True
            result.append(ch)
            i += 1
            continue
        if ch == '/' and i + 1 < len(text) and text[i + 1] == '/':
            # Line comment — skip to end of line
            while i < len(text) and text[i] != '\n':
                i += 1
            continue
        if ch == '/' and i + 1 < len(text) and text[i + 1] == '*':
            # Block comment — skip to */
            i += 2
            while i + 1 < len(text) and not (text[i] == '*' and text[i + 1] == '/'):
                i += 1
            i += 2
            continue
        result.append(ch)
        i += 1
    return ''.join(result)

def load_jsonc(path):
    with open(path) as f:
        text = f.read()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # String-aware comment stripping (preserves // inside quoted strings)
    stripped = _strip_jsonc_comments(text)
    stripped = re.sub(r',\s*([}\\]])', r'\1', stripped)  # trailing commas
    return json.loads(stripped)

existing = {}
if live_path:
    try:
        existing = load_jsonc(live_path)
    except FileNotFoundError:
        existing = {}
    except Exception as e:
        sys.stderr.write("!! Could not parse live opencode.jsonc (%s); "
                         "starting from empty base.\n" % e)
        existing = {}
if not isinstance(existing, dict):
    existing = {}

# --- get_limits() heuristic (verbatim port of Docker reference) ------------
def get_limits(model_id):
    name = model_id.lower()
    bare = name.split('/', 1)[-1] if '/' in name else name
    if any(p in name for p in ['openrouter/', 'vertex_ai/', 'cli-proxy-api/']):
        name = bare
    if 'gpt-4.1' in name:
        return 1048576, 32768
    if 'gpt-4o' in name:
        return 128000, 16384
    if 'gpt-4-turbo' in name:
        return 128000, 4096
    if re.search(r'gpt-4[\.-]', name) or name.endswith('gpt-4'):
        return 8192, 4096
    if 'gpt-3.5' in name:
        return 16384, 4096
    if 'gpt-5' in name:
        return 128000, 16384
    if re.search(r'/o[134]', name) or re.search(r'-o[134]', name):
        return 200000, 100000
    if re.search(r'claude-[34]', name):
        if re.search(r'claude-3\.7|claude-[45]', name):
            return 200000, 16384
        return 200000, 4096
    if 'deepseek' in name:
        return 128000, 8192
    if 'glm-5.2' in name:
        return 1048576, 131072
    if 'glm' in name:
        return 128000, 8192
    if 'llama_cpp' in model_id:
        # Quantized qwen3.6-27b GGUF has 256K real context, not the 200K default
        if 'qwen3.6-27b' in name:
            return 262144, 32768
        return 200000, 32768
    if 'gemini' in name:
        return 1048576, 65536
    return 128000, 8192

# --- Read discovered models from file ----------------------------------------
discovered = []
try:
    with open(models_file) as f:
        for line in f:
            mid = line.strip()
            if mid:
                discovered.append(mid)
except (FileNotFoundError, TypeError):
    pass

# --- Read fallback model chain from env ------------------------------------
fallback_chain = []
fallback_raw = os.environ.get("OPENCODE_FALLBACK_MODEL", "")
if fallback_raw:
    for entry in fallback_raw.split(","):
        fb = entry.strip()
        if not fb:
            continue
        fallback_chain.append(normalize_model_id(fb))

# --- Apply the merge (only target keys) -------------------------------------
# Normalize all model fields using the single source-of-truth function
existing["model"] = normalize_model_id(default_model)
existing["small_model"] = normalize_model_id(small_model)

# Agent build + plan model
agent = existing.setdefault("agent", {})
if not isinstance(agent, dict):
    agent = {}
    existing["agent"] = agent
agent_build = agent.setdefault("build", {})
if not isinstance(agent_build, dict):
    agent_build = {}
    agent["build"] = agent_build
agent_plan = agent.setdefault("plan", {})
if not isinstance(agent_plan, dict):
    agent_plan = {}
    agent["plan"] = agent_plan
agent_build_model_before = agent_build.get("model")
agent_plan_model_before = agent_plan.get("model")
_agent_model = normalize_model_id(agent_model)
agent_build["model"] = _agent_model
agent_plan["model"] = _agent_model

# --- Generate provider blocks (data-driven from PROVIDER_BLOCKS) ------------
added = []
lc_added = []
provider = existing.setdefault("provider", {})
if not isinstance(provider, dict):
    provider = {}
    existing["provider"] = provider

for name, cfg in PROVIDER_BLOCKS.items():
    pentry = provider.setdefault(name, {})
    if not isinstance(pentry, dict):
        pentry = {}
        provider[name] = pentry
    # npm package (optional — only litellm and llama_cpp have one)
    if "npm" in cfg:
        pentry["npm"] = cfg["npm"]
    # options dict (merge into existing)
    opts = pentry.setdefault("options", {})
    if not isinstance(opts, dict):
        opts = {}
        pentry["options"] = opts
    for k, v in cfg.get("options", {}).items():
        opts[k] = v
    # models map (optional — only providers with a filter get one)
    if "filter" in cfg:
        mm = pentry.setdefault("models", {})
        if not isinstance(mm, dict):
            mm = {}
            pentry["models"] = mm
        for mid in discovered:
            if not cfg["filter"](mid):
                continue
            key = mid
            if "strip_prefix" in cfg and mid.startswith(cfg["strip_prefix"]):
                key = mid[len(cfg["strip_prefix"]):]
            if key not in mm:
                ctx, out = get_limits(mid)
                mm[key] = {
                    "name": mid,
                    "limit": {"context": ctx, "output": out},
                }
                if name == "llama_cpp":
                    lc_added.append(key)
                else:
                    added.append(mid)

# --- Plugin array ------------------------------------------------------------
plugins = existing.get("plugin")
if not plugins or not isinstance(plugins, list):
    existing["plugin"] = [
        "@tarquinen/opencode-dcp@latest",
        "@franlol/opencode-md-table-formatter@latest",
        "cc-safety-net",
    ]
if fallback_chain and "opencode-runtime-fallback" not in existing["plugin"]:
    existing["plugin"].append("opencode-runtime-fallback")

# --- Write staging (strict JSON — json.tool compatible) --------------------
with open(out_path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")

# --- Write fallback staging file -------------------------------------------
fallback_path = os.path.join(os.path.dirname(out_path), "opencode-fallback.jsonc")
if fallback_chain:
    with open(fallback_path, "w") as ff:
        json.dump({"fallback_models": fallback_chain}, ff, indent=2)
        ff.write("\n")

# --- Emit diff/merge summary -----------------------------------------------
total_models = len(provider.get("litellm", {}).get("models", {}))
existing_count = total_models - len(added)
lines = []
lines.append("OpenCode merge summary")
lines.append("=" * 40)
lines.append("top-level model       -> %s" % existing.get("model"))
lines.append("top-level small_model -> %s" % existing.get("small_model"))
lines.append("agent.build.model     -> %s" % agent_build.get("model"))
lines.append("agent.plan.model      -> %s" % agent_plan.get("model"))
if agent_build_model_before and agent_build_model_before != existing.get("model"):
    lines.append("  (was agent.build.model = %s)" % agent_build_model_before)
if agent_plan_model_before and agent_plan_model_before != existing.get("model"):
    lines.append("  (was agent.plan.model = %s)" % agent_plan_model_before)
lines.append("provider.opencode     -> present (apiKey={env:OPENCODE_ZEN_API_KEY})")
lines.append("provider.litellm      -> apiKey={env:OPENAI_API_KEY}, baseURL=%s"
             % base_url)
lines.append("litellm.models total  -> %d (%d preserved + %d newly added)"
             % (total_models, existing_count, len(added)))
# llama_cpp provider summary
lc_total = len(provider.get("llama_cpp", {}).get("models", {}))
lc_existing_count = lc_total - len(lc_added)
lines.append("provider.llama_cpp    -> apiKey={env:OPENAI_API_KEY}, baseURL=%s"
             % base_url)
lines.append("llama_cpp.models total-> %d (%d preserved + %d newly added)"
             % (lc_total, lc_existing_count, len(lc_added)))
if fallback_chain:
    lines.append("fallback chain        -> [%s]" % ", ".join(fallback_chain))
    lines.append("  (written to opencode-fallback.jsonc in staging dir)")
lines.append("")
lines.append("Newly added models (first 30):")
for m in added[:30]:
    lines.append("  + %s" % m)
if len(added) > 30:
    lines.append("  ... and %d more" % (len(added) - 30))
lines.append("")
preserved_blocks = []
for key in ("permission", "plugin"):
    if key in existing:
        preserved_blocks.append(key)
lines.append("Preserved blocks: %s" % ", ".join(preserved_blocks))
# agent block is PARTIALLY preserved: its model fields are overridden to the
# normalized model; all other agent sub-block fields (mode, description, etc.)
# are kept untouched.
if "agent" in existing:
    lines.append("agent block: preserved (other fields) + model overridden -> %s"
                 % _agent_model)
summary = "\n".join(lines)
with open(diff_path, "w") as f:
    f.write(summary + "\n")
print(summary)
PYEOF
}
