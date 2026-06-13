# lib/config-opencode.sh — OpenCode opencode.jsonc MERGE generator (host)
#
# THE MOST IMPORTANT REQUIREMENT (REQ 4 / EC5): the existing
# ~/.config/opencode/opencode.jsonc has hand-tuned content that MUST be
# preserved (permission deny-list, plugin array, agent build/plan blocks,
# server block, experimental, existing provider.litellm.models map). We never
# overwrite the live file — we deep-merge ONLY the target keys and write the
# result to STAGING_DIR for the orchestrator to review/apply later.
#
# Merge policy:
#   (a) ensure provider.opencode with options.apiKey == "{env:OPENCODE_API_KEY}"
#   (b) set top-level "model" + "small_model" to the FREE Zen model
#   (c) provider.litellm.options.apiKey  -> "{env:OPENAI_API_KEY}"
#       provider.litellm.options.baseURL -> resolved LITELLM_BASE_URL
#   (d) union-merge provider.litellm.models with $DISCOVERED_MODELS
#       (existing hand-tuned limits are PRESERVED; newly discovered models are
#        added with computed get_limits() heuristics — surgical, lossless)
#   (e) everything else untouched

# get_limits heuristics (ported verbatim from Docker config-opencode.sh).
_oc_get_limits() { :; }  # implemented in python below for fidelity

# generate_opencode_staging — merge live opencode.jsonc -> STAGING_OPENCODE.
# Args: none. Reads $DISCOVERED_MODELS from stdin (newline-separated).
generate_opencode_staging() {
    mkdir -p "$(dirname "$STAGING_OPENCODE")"

    local live_cfg="${OPENCODE_CONFIG}"
    local staging="${STAGING_OPENCODE}"
    local free_model="${OPENCODE_FREE_MODEL}"
    local base_url="${LITELLM_BASE_URL}"
    local diff_file="${STAGING_DIFF}"
    local models_file="${STAGING_MODELS}"

    python3 - \
        "$live_cfg" "$staging" "$free_model" "$base_url" "$diff_file" \
        "$models_file" << 'PYEOF'
import sys, json, re

live_path, out_path, free_model, base_url, diff_path, models_file = (
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
    if 'glm' in name:
        return 128000, 8192
    if 'llama_cpp' in model_id:
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
oc_opts["apiKey"] = "{env:OPENCODE_API_KEY}"

# (b) top-level model + small_model -> FREE Zen model (saves paid quota)
existing["model"] = free_model
existing["small_model"] = free_model

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

# --- Emit diff/merge summary -----------------------------------------------
total_models = len(models_map)
existing_count = total_models - len(added)
lines = []
lines.append("OpenCode merge summary")
lines.append("=" * 40)
lines.append("top-level model       -> %s" % existing.get("model"))
lines.append("top-level small_model -> %s" % existing.get("small_model"))
lines.append("provider.opencode     -> present (apiKey={env:OPENCODE_API_KEY})")
lines.append("provider.litellm      -> apiKey={env:OPENAI_API_KEY}, baseURL=%s"
             % base_url)
lines.append("litellm.models total  -> %d (%d preserved + %d newly added)"
             % (total_models, existing_count, len(added)))
lines.append("")
lines.append("Newly added models (first 30):")
for m in added[:30]:
    lines.append("  + %s" % m)
if len(added) > 30:
    lines.append("  ... and %d more" % (len(added) - 30))
lines.append("")
preserved_blocks = []
for key in ("permission", "plugin", "agent", "server", "experimental"):
    if key in existing:
        preserved_blocks.append(key)
lines.append("Preserved blocks: %s" % ", ".join(preserved_blocks))
summary = "\n".join(lines)
with open(diff_path, "w") as f:
    f.write(summary + "\n")
print(summary)
PYEOF
}
