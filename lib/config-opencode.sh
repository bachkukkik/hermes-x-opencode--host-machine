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

# get_limits heuristics (ported verbatim from Docker config-opencode.sh).
_oc_get_limits() { :; }  # implemented in python below for fidelity

# generate_opencode_staging — merge live opencode.jsonc -> STAGING_OPENCODE.
# Args: none. Reads $DISCOVERED_MODELS from stdin (newline-separated).
generate_opencode_staging() {
    mkdir -p "$(dirname "$STAGING_OPENCODE")"

    local live_cfg="${OPENCODE_CONFIG}"
    local staging="${STAGING_OPENCODE}"
    local default_model="${OPENCODE_DEFAULT_MODEL}"
    local base_url="${OPENAI_BASE_URL}"
    local diff_file="${STAGING_DIFF}"
    local models_file="${STAGING_MODELS}"

    python3 - \
        "$live_cfg" "$staging" "$default_model" "$base_url" "$diff_file" \
        "$models_file" << 'PYEOF'
import sys, json, re, os

live_path, out_path, default_model, base_url, diff_path, models_file = (
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5],
    sys.argv[6],
)

# --- Tolerant JSONC input parser -------------------------------------------
def load_jsonc(path):
    with open(path) as f:
        text = f.read()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # Strip // line comments and /* */ block comments (naive but safe for
    # config files — no model id legitimately contains these sequences).
    stripped = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    stripped = re.sub(r'(?m)//.*$', '', stripped)
    stripped = re.sub(r',\s*([}\]])', r'\1', stripped)  # trailing commas
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
        # Resolve provider prefix
        if fb.startswith("opencode/"):
            fb_full = fb
        elif fb.startswith("litellm/"):
            fb_full = fb
        elif fb.startswith("llama_cpp/"):
            # llama_cpp/* models have their own provider block now
            fb_full = fb
        else:
            # Bare model -> prefix with litellm/ (proxy is available)
            fb_full = "litellm/" + fb
        fallback_chain.append(fb_full)

# --- Apply the merge (only target keys) -------------------------------------
# (a) provider.opencode — free Zen auth
provider = existing.setdefault("provider", {})
if not isinstance(provider, dict):
    provider = {}
    existing["provider"] = provider
oc = provider.setdefault("opencode", {})
if not isinstance(oc, dict):
    oc = {}
    provider["opencode"] = oc
oc_opts = oc.setdefault("options", {})
if not isinstance(oc_opts, dict):
    oc_opts = {}
    oc["options"] = oc_opts
oc_opts["apiKey"] = "{env:OPENCODE_ZEN_API_KEY}"

# (b) top-level model + small_model -> default model (saves paid quota)
existing["model"] = default_model
# Allow OPENCODE_SMALL_MODEL to override small_model, fall back to OPENCODE_DEFAULT_MODEL
_small_model = os.environ.get("OPENCODE_SMALL_MODEL", "").strip()
if not _small_model:
    _small_model = os.environ.get("OPENCODE_DEFAULT_MODEL", "").strip()
existing["small_model"] = _small_model if _small_model else default_model

# (b.1) agent.build.model + agent.plan.model -> FREE Zen model. The live config
# may pin a PAID model here (e.g. litellm/zai/glm-5.1); without overriding these
# sub-models the top-level switch is defeated. Other agent sub-block fields
# (mode, description, etc.) are preserved untouched. Blocks created minimally
# if absent so we never clobber a hand-tuned agent block.
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
agent_build["model"] = default_model
agent_plan["model"] = default_model

# (c)+(d) provider.litellm — refresh models map + credentials
ll = provider.setdefault("litellm", {})
if not isinstance(ll, dict):
    ll = {}
    provider["litellm"] = ll
ll_opts = ll.setdefault("options", {})
if not isinstance(ll_opts, dict):
    ll_opts = {}
    ll["options"] = ll_opts
ll_opts["apiKey"] = "{env:OPENAI_API_KEY}"
ll_opts["baseURL"] = base_url

models_map = ll.setdefault("models", {})
if not isinstance(models_map, dict):
    models_map = {}
    ll["models"] = models_map

# (e) provider.llama_cpp — route llama_cpp/* models through the same LiteLLM
#     proxy. Models like llama_cpp/qwen3.6-27b-q4_k_m are served via wildcard
#     routing in LiteLLM (not listed by /v1/models but routable). Without this
#     block, opencode resolves "llama_cpp/xxx" -> looks for provider.llama_cpp,
#     finds none, and throws ProviderModelNotFoundError.
lc = provider.setdefault("llama_cpp", {})
if not isinstance(lc, dict):
    lc = {}
    provider["llama_cpp"] = lc
lc["npm"] = "@ai-sdk/openai-compatible"
lc_opts = lc.setdefault("options", {})
if not isinstance(lc_opts, dict):
    lc_opts = {}
    lc["options"] = lc_opts
lc_opts["apiKey"] = "{env:OPENAI_API_KEY}"
lc_opts["baseURL"] = base_url
lc_opts["timeout"] = 600000
lc_opts["setCacheKey"] = True
# Populate models map with discovered llama_cpp/* models
lc_models_map = lc.setdefault("models", {})
if not isinstance(lc_models_map, dict):
    lc_models_map = {}
    lc["models"] = lc_models_map
lc_added = []
for mid in discovered:
    if mid.startswith("llama_cpp/"):
        bare = mid[len("llama_cpp/"):]
        if bare not in lc_models_map:
            ctx, out = get_limits(mid)
            lc_models_map[bare] = {
                "name": mid,
                "limit": {"context": ctx, "output": out},
            }
            lc_added.append(bare)

added = []
for mid in discovered:
    if mid not in models_map:
        ctx, out = get_limits(mid)
        models_map[mid] = {
            "name": mid,
            "limit": {"context": ctx, "output": out},
        }
        added.append(mid)

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
total_models = len(models_map)
existing_count = total_models - len(added)
lines = []
lines.append("OpenCode merge summary")
lines.append("=" * 40)
lines.append("top-level model       -> %s" % existing.get("model"))
lines.append("top-level small_model -> %s" % existing.get("small_model"))
lines.append("agent.build.model     -> %s" % agent_build.get("model"))
lines.append("agent.plan.model      -> %s" % agent_plan.get("model"))
if agent_build_model_before and agent_build_model_before != default_model:
    lines.append("  (was agent.build.model = %s)" % agent_build_model_before)
if agent_plan_model_before and agent_plan_model_before != default_model:
    lines.append("  (was agent.plan.model = %s)" % agent_plan_model_before)
lines.append("provider.opencode     -> present (apiKey={env:OPENCODE_ZEN_API_KEY})")
lines.append("provider.litellm      -> apiKey={env:OPENAI_API_KEY}, baseURL=%s"
             % base_url)
lines.append("litellm.models total  -> %d (%d preserved + %d newly added)"
             % (total_models, existing_count, len(added)))
# llama_cpp provider summary
lc_total = len(lc_models_map)
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
for key in ("permission", "plugin", "server", "experimental"):
    if key in existing:
        preserved_blocks.append(key)
lines.append("Preserved blocks: %s" % ", ".join(preserved_blocks))
# agent block is PARTIALLY preserved: its model fields are overridden to the
# free Zen model (see above); all other agent sub-block fields (mode,
# description, etc.) are kept untouched.
if "agent" in existing:
    lines.append("agent block: preserved (other fields) + model overridden -> %s"
                 % default_model)
summary = "\n".join(lines)
with open(diff_path, "w") as f:
    f.write(summary + "\n")
print(summary)
PYEOF
}
