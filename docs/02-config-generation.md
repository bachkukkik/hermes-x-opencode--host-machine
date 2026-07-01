# 02 — Config Generation

## What

The config generation subsystem produces merged OpenCode and Hermes config files by injecting discovered models and credentials into existing live configs while preserving all non-target content.

## Why

- OpenCode configs evolve over time — users add custom plugins, permission rules, and agent behavior blocks. Overwriting the entire file on every generation cycle destroys these customizations.
- Hermes configs carry multiple `custom_providers` entries, skills, tools, and platform blocks. A naive replacement would require the user to re-tune everything after every model refresh.
- The MERGE strategy surgically updates only the fields that depend on the model list (provider entries, model references, credentials) and leaves everything else untouched.

## How

### constants.sh paths

The single source of truth for all filesystem paths and defaults:

| Variable | Value | Purpose |
|----------|-------|---------|
| `HERMES_HOME` | `${HOME}/.hermes` | Hermes root directory |
| `CONFIG` | `${HERMES_HOME}/config.yaml` | Live Hermes config |
| `HERMES_ENV` | `${HERMES_HOME}/.env` | Environment variables |
| `OPENCODE_CONFIG` | `${HOME}/.config/opencode/opencode.jsonc` | Live OpenCode config |
| `OPENCODE_AUTH` | `${HOME}/.local/share/opencode/auth.json` | OpenCode credential store |
| `STAGING_DIR` | `${HERMES_HOME}/host-config-gen/staging` | Output directory |
| `OPENAI_BASE_URL` | `http://localhost:4000` | OpenAI-compatible endpoint (env-overridable) |
| `OPENAI_DEFAULT_MODEL` | `zai/glm-5.2` | Fallback model (EC1) |
| `OPENCODE_FREE_MODEL` | `opencode/deepseek-v4-flash-free` | Zero-cost Zen model for delegation |

### config-opencode.sh MERGE strategy

The OpenCode config generator does NOT replace the live file. It reads the existing `opencode.jsonc` (tolerant JSONC parser strips `//` and `/**/` comments), applies a surgical merge, and writes only to staging:

```jsonc
// BEFORE (live ~/.config/opencode/opencode.jsonc)
{
  "permission": { "deny": ["rm", "sudo"] },
  "plugin": ["my-custom-plugin"],
  "agent": {
    "build": { "model": "litellm/zai/glm-5.1", "mode": "fast" },
    "plan": { "model": "litellm/zai/glm-5.1", "mode": "deep" }
  }
}

// AFTER (staging — note what changed vs. what survived)
{
  "model": "opencode/deepseek-v4-flash-free",           // ← injected (free Zen)
  "small_model": "opencode/deepseek-v4-flash-free",     // ← injected
  "provider": {
    "opencode": {
      "options": { "apiKey": "{env:OPENCODE_API_KEY}" } // ← injected
    },
    "litellm": {
      "options": {
        "apiKey": "{env:OPENAI_API_KEY}",               // ← injected
        "baseURL": "http://localhost:4000"               // ← injected
      },
      "models": {                                        // ← union-merged
        "zai/glm-5.2": { "name": "zai/glm-5.2", "limit": {"context": 1048576, "output": 131072} }
        // ... all discovered models
      }
    }
  },
  "permission": { "deny": ["rm", "sudo"] },             // ← preserved
  "plugin": ["my-custom-plugin"],                        // ← preserved
  "agent": {
    "build": { "model": "opencode/deepseek-v4-flash-free", "mode": "fast" },  // model overridden, mode preserved
    "plan": { "model": "opencode/deepseek-v4-flash-free", "mode": "deep" }    // model overridden, mode preserved
  }
}
```

**Merge policy:**

| Target key | Action | Rationale |
|-----------|--------|-----------|
| `provider.opencode` | Ensure present with `{env:OPENCODE_API_KEY}` | Free Zen auth for delegation |
| `model`, `small_model` | Set to `OPENCODE_FREE_MODEL` | Zero paid quota for coding subagents |
| `agent.build.model`, `agent.plan.model` | Override to free Zen model | Defeats paid-model pinning in sub-agents |
| `agent.*` (other fields) | Preserve | Mode, description, etc. survive |
| `provider.litellm.models` | Union-merge discovered models | Existing limits preserved; new models added |
| `permission`, `plugin`, `server`, `experimental` | Preserve | Hand-tuned blocks untouched |

### config-hermes.sh overlay

The Hermes overlay generator emits a **Form B** `custom_providers` entry — a static `models:` map that lists every discovered model with pre-computed context lengths. This avoids Hermes probing the LiteLLM endpoint at runtime.

Context length resolution uses a `resolve_ctx_len()` function (bash + equivalent Python in the heredoc) with a longest-match-first pin table covering **13 model families**. The call pattern is:

```bash
resolve_ctx_len() {
    local model="$1"
    local m=$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')
    case "$m" in
        # Longest/most-specific patterns first (first match wins)
        *glm-5.2*)           echo 1048576 ;;  # agent misreports as 202752
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
        *qwen3.6-27b*q4*)    echo 262144  ;;  # quantized GGUF
        *qwen3.6*)           echo 1048576 ;;
        *)                   echo ""      ;;  # unknown → {}
    esac
}
```

**Resolution rules (per model):**

| Pattern | Context length | Rationale |
|---------|---------------|-----------|
| `*glm-5.2*` | 1,048,576 | Agent catch-all gives 202,752 (wrong) |
| `*claude-opus-4*` | 1,000,000 | Anthropic's reported maximum |
| `*claude-sonnet-4.6*` | 1,000,000 | Anthropic's reported maximum |
| `*gpt-5.4*` | 1,050,000 | Most specific GPT-5 pin |
| `*gpt-5*` | 400,000 | Conservative for all other GPT-5 variants |
| `*gpt-4o*` | 128,000 | OpenAI GPT-4o context window |
| `*gpt-4.1*` | 1,047,576 | OpenAI GPT-4.1 context window |
| `*gpt-4*` | 128,000 | Generic GPT-4 catch-all |
| `*gemini*` | 1,048,576 | Google Gemini context window |
| `*deepseek-v4*` | 1,000,000 | DeepSeek V4 maximum context |
| `*minimax-m3*` | 1,000,000 | MiniMax M3 maximum context |
| `*qwen3.6-27b*q4*` | 262,144 | Quantized GGUF real context (not family 1M) |
| `*qwen3.6*` | 1,048,576 | Qwen 3.6 full context |
| (unknown, non-default) | `{}` (empty mapping) | Agent self-resolves via `DEFAULT_CONTEXT_LENGTHS` / `models.dev` / endpoint probe |
| (unknown, IS default model) | 200,000 | Fallback: guarantees overlay has ≥1 explicit `context_length` entry so the active model gets a sane window |

The existing `api_key` is carried forward from the live config. Other `custom_providers` entries are preserved. Model settings (`model.default`, `model.name`) are set to `OPENAI_DEFAULT_MODEL` only if absent.

### Environment-gated config blocks

Beyond the `custom_providers` overlay, `config-hermes.sh` emits optional YAML blocks gated on environment variables. These blocks live in the generated `config-hermes-overlay.yaml` alongside the `custom_providers` entry:

| Env var | Default | Writes to config.yaml | Effect |
|---------|---------|-----------------------|--------|
| `HERMES_YOLO_MODE` | *(off)* | `approvals:\n  mode: off` | Only when set to `"1"`. Skips the manual approval prompt before dangerous shell commands — equivalent to launching Hermes with `--yolo`. |
| `HERMES_DELEGATION_MAX_ITERATIONS` | `50` | `delegation:\n  max_iterations: <N>` | Caps how many iterations a `delegate_task` subagent loop may run. Always present (default 50). |
| `HERMES_GOAL_MAX_TURNS` | `50` | `goals:\n  max_turns: <N>` | Caps how many turns a goal-driven task may run. Always present (default 50). |
| `HERMES_COMPRESSION_THRESHOLD` | *(unset)* | `context_compression:\n  threshold: <float>` | Only when set to a parseable float. Triggers context compression when token usage exceeds this fraction (0.0–1.0). |

**Block generation logic (Python, inside `generate_hermes_overlay` heredoc):**

```python
# approvals.mode: off  (when HERMES_YOLO_MODE=1)
if os.environ.get("HERMES_YOLO_MODE") == "1":
    cfg["approvals"] = {"mode": "off"}

# goals.max_turns  (default 50)
goal_max_turns = int(os.environ.get("HERMES_GOAL_MAX_TURNS", "50"))
cfg["goals"] = {"max_turns": goal_max_turns}

# delegation.max_iterations  (default 50)
deleg_max_iter = int(os.environ.get("HERMES_DELEGATION_MAX_ITERATIONS", "50"))
cfg["delegation"] = {"max_iterations": deleg_max_iter}

# context_compression.threshold  (when HERMES_COMPRESSION_THRESHOLD is set)
_compression_threshold = os.environ.get("HERMES_COMPRESSION_THRESHOLD", "").strip()
if _compression_threshold:
    try:
        cfg.setdefault("context_compression", {})["threshold"] = float(_compression_threshold)
    except ValueError:
        pass
```

Key behaviors:
- **YOLO is the only conditional block.** `goals.max_turns` and `delegation.max_iterations` are always present with effective defaults of 50, regardless of YOLO mode.
- **Compression is opt-in.** `context_compression.threshold` is only written when `HERMES_COMPRESSION_THRESHOLD` is set to a valid float; otherwise the key is absent and Hermes uses its internal default.
- **All blocks co-exist** with `custom_providers` and `model` in the same staging overlay.

### env-auth.sh credential staging

Seeds `auth.json` with two providers:

| Provider | Key source | Fallback |
|----------|-----------|----------|
| `opencode` (Zen) | `OPENCODE_ZEN_API_KEY` from `~/.hermes/.env` | None — must be present |
| `litellm` (proxy) | `OPENAI_API_KEY` from `~/.hermes/.env` | `model.api_key` from `config.yaml` |

### Environment variable reference

| Variable | Purpose | Set in | Referenced by |
|----------|---------|--------|---------------|
| `OPENCODE_ZEN_API_KEY` | OpenCode Zen free-tier credential | `~/.hermes/.env` | `env-auth.sh` (read in-process) |
| `OPENCODE_API_KEY` | Resolves `{env:OPENCODE_API_KEY}` in opencode.jsonc | Shell env or `~/.hermes/.env` | OpenCode runtime |
| `OPENAI_API_KEY` | LiteLLM proxy credential | `~/.hermes/.env` or `config.yaml` `model.api_key` | `{env:OPENAI_API_KEY}` in opencode.jsonc |
| `OPENAI_BASE_URL` | OpenAI-compatible endpoint URL | Shell env (default `http://localhost:4000`) | All modules |

### Fallback chain

```
OPENCODE_FALLBACK_MODEL (comma-separated) ──► opencode-fallback.jsonc
                                                    │
                    ┌───────────────────────────────┘
                    ▼
        opencode-runtime-fallback plugin

EC6: OPENAI_API_KEY not in .env ──► config.yaml model.api_key ──► custom_providers[].api_key
```

## Verification

```bash
# Run the full config generation pipeline
cd ~/.hermes/host-config-gen
bash generate.sh --dry-run

# Verify OpenCode staging preserves custom blocks
grep -q '"permission"' staging/opencode.jsonc && echo "permission block preserved"
grep -q '"plugin"' staging/opencode.jsonc && echo "plugin block preserved"

# Confirm free Zen model is applied correctly
grep -q '"model": "opencode/deepseek-v4-flash-free"' staging/opencode.jsonc
grep -q '"apiKey": "{env:OPENCODE_API_KEY}"' staging/opencode.jsonc

# Verify Hermes overlay has model entries
python3 -c "
import yaml
cfg = yaml.safe_load(open('staging/config-hermes-overlay.yaml'))
cp = [c for c in cfg.get('custom_providers',[]) if c.get('name')=='litellm']
assert cp, 'litellm provider missing'
assert len(cp[0].get('models',{})) > 1, 'no models in map'
print(f'Models: {len(cp[0][\"models\"])}')
"

# Verify auth.json has both providers
grep -q '"opencode"' staging/auth.json && echo "opencode provider seeded"
grep -q '"litellm"' staging/auth.json && echo "litellm provider seeded"
```

## What Works

- OpenCode MERGE preserves all hand-tuned blocks (permission, plugin, server, experimental, agent mode/description)
- Top-level `model`/`small_model` and agent sub-block models are overridden to the free Zen model
- Existing `provider.litellm.models` entries are preserved; new models are union-merged with `get_limits()` heuristics
- Hermes overlay carries forward all non-litellm `custom_providers` entries
- Both provider credentials are seeded in staging `auth.json` from `.env` with `config.yaml` fallback

## What Fails

- **Corrupt live JSONC:** If `opencode.jsonc` contains unparseable content, the generator starts from an empty base — all custom blocks are lost in staging.
- **Missing Zen key:** If `OPENCODE_ZEN_API_KEY` is absent from `~/.hermes/.env`, the `opencode` provider in `auth.json` is not seeded — OpenCode Zen auth fails at runtime.
- **Agent sub-block model pin:** If the live config pins a paid model in `agent.build.model` or `agent.plan.model` and the MERGE doesn't override it, the free-mission objective is defeated. The generator explicitly overrides these sub-block models.

## Resolution

- **Corrupt live JSONC:** Run `python3 -m json.tool` on the live config after manually fixing the syntax. The tolerant JSONC parser strips comments; issues are typically trailing commas or unclosed braces.
- **Missing Zen key:** Add `OPENCODE_ZEN_API_KEY=<your-key>` to `~/.hermes/.env`. Then export `OPENCODE_API_KEY` with the same value so `{env:OPENCODE_API_KEY}` resolves correctly.
- **Agent sub-block model pin:** The generator overrides `agent.build.model` and `agent.plan.model` to the free Zen model. Other agent fields (mode, description) are preserved. If the override fails, check the staging diff in `staging/opencode-merge-summary.txt`.

## Verdict

The MERGE strategy correctly balances model-list refresh with config preservation. The surgical merge targets (provider blocks, model references, credentials) are well-isolated from hand-tuned content. The two-env-var credential pattern (`OPENCODE_ZEN_API_KEY` + `OPENCODE_API_KEY`) is a necessary redundancy for OpenCode's `{env:VAR}` resolution mechanism.
