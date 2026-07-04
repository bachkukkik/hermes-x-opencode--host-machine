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
| `OPENCODE_DEFAULT_MODEL` | `$OPENCODE_DEFAULT_MODEL` | Dynamic — defaults in `.env.example`; overrides hard-coded Zen model |

### Multi-provider OPENCODE_*_MODEL routing

Three environment variables control which model OpenCode uses, and each accepts an optional provider prefix that routes the request through the correct auth block:

| Variable | Purpose | Default |
|----------|---------|---------|
| `OPENCODE_DEFAULT_MODEL` | Top-level `model`, `small_model`, and agent sub-block models | `opencode/deepseek-v4-flash-free` |
| `OPENCODE_SMALL_MODEL` | Lightweight tasks (summarization, formatting). Falls back to `OPENCODE_DEFAULT_MODEL` if unset | Same as `OPENCODE_DEFAULT_MODEL` |
| `OPENCODE_FALLBACK_MODEL` | Comma-separated chain tried in order when default/small fail. Bare models (no prefix) auto-get `litellm/` | *(unset)* |

**Provider prefixes:**

| Prefix | Provider block in opencode.jsonc | Auth source | Example |
|--------|----------------------------------|-------------|---------|
| `opencode/<model>` | `provider.opencode` | `{env:OPENCODE_ZEN_API_KEY}` | `opencode/deepseek-v4-flash-free` |
| `litellm/<model>` | `provider.litellm` | `{env:OPENAI_API_KEY}` + `baseURL` | `litellm/openai/gpt-4o-mini` |
| `llama_cpp/<model>` | `provider.llama_cpp` | `{env:OPENAI_API_KEY}` + `baseURL` + `timeout: 600000` | `llama_cpp/qwen3.6-27b-q4_k_m` |
| *(none)* | Auto-resolves to `litellm/<model>` | `{env:OPENAI_API_KEY}` | `zai/glm-5.2` → `litellm/zai/glm-5.2` |

The generator passes these values through verbatim — it does not rewrite prefixes. The only transformation is auto-prefixing bare models in `OPENCODE_FALLBACK_MODEL` with `litellm/`. This means a model like `litellm/deepseek/deepseek-v4-pro` (nested provider path) works as-is.

**Fallback chain generation** (`opencode-fallback.jsonc`):

```
OPENCODE_FALLBACK_MODEL=litellm/zai/glm-5.2,llama_cpp/qwen3.6-27b-q4_k_m,zai/glm-5.2
                                          │               │
                                          ▼               ▼ (bare → litellm auto-prefix)
fallback_models = [
  "litellm/zai/glm-5.2",
  "llama_cpp/qwen3.6-27b-q4_k_m",
  "litellm/zai/glm-5.2"
]
```

### Portable .env sourcing

The repo uses a **portable .env pattern** — scripts source environment variables relative to their own location, not from a fixed home-directory path. This makes the repository the single source of truth and enables clean install-to-deploy workflows.

**How it works:**

| Script | Behavior |
|--------|----------|
| `generate.sh` | Sources `${SCRIPT_DIR}/.env` (computed via `SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)`) — not `~/.hermes/.env` |
| `install.sh` | Copies `.env` from the repo alongside `generate.sh` into the deployed directory |

**Workflow:**

```
Edit .env in repo
       │
       ▼
bash install.sh          →  copies .env + scripts to deployed location (e.g., ~/.hermes/host-config-gen/)
       │
       ▼
bash generate.sh         →  sources ${SCRIPT_DIR}/.env — reads the .env sitting next to it
```

**Why this matters:**

- **Repo is the source of truth.** `.env` lives in the repo, under version control (gitignored for secrets, but `.env.example` is tracked). Users edit it once and propagate via `install.sh`.
- **No home-directory coupling.** `generate.sh` does not hardcode `~/.hermes/.env` — it sources from whatever directory it was deployed to. This means you can deploy to any path and the scripts still find their `.env`.
- **Idempotent installs.** Running `install.sh` again copies the latest `.env` from the repo, so changes made in the repo flow to the deployed location without manual file syncing.

**Key convention:** Never source `.env` from `~/.hermes/.env` inside `generate.sh` or `install.sh`. The `.env` that matters is always the one colocated with the script (`${SCRIPT_DIR}/.env`).

### Environment variable export (Python subprocess bridge)

The `.env` file uses `KEY=value` syntax (not `export KEY=value`), so `source .env` creates **shell variables** only — Python subprocesses cannot see them via `os.environ.get()`. The `generate.sh` bridges this gap:

```bash
source "${SCRIPT_DIR}/.env" 2>/dev/null || true
export OPENAI_API_KEY OPENAI_BASE_URL
export OPENCODE_DEFAULT_MODEL OPENCODE_SMALL_MODEL OPENCODE_AGENT_MODEL
export OPENCODE_FALLBACK_MODEL OPENAI_DEFAULT_MODEL HERMES_DEFAULT_MODEL
export HERMES_YOLO_MODE HERMES_GOAL_MAX_TURNS HERMES_DELEGATION_MAX_ITERATIONS
export HERMES_DELEGATION_MODEL HERMES_DELEGATION_PROVIDER HERMES_COMPRESSION_THRESHOLD
```

The `export` statements promote the shell variables to environment variables so Python's `os.environ.get()` sees the correct values. This is why `.env` changes take effect without needing `export` inside the `.env` file itself.

#### Sourceable export-env.sh (for opencode delegation)

The export bridge above only applies within the generator's own process tree. But `opencode run` resolves `{env:OPENAI_API_KEY}` from the **interactive shell** environment — a shell where the generator never ran. To bridge this, the generator writes `staging/export-env.sh`: a sourceable script with all managed env vars baked in (values expanded at generation time from the sourced `.env`).

`--apply` deploys it to `~/.hermes/host-config-gen/export-env.sh`. Before running opencode in a fresh shell:

```bash
source ~/.hermes/host-config-gen/export-env.sh
```

This is required because `opencode.jsonc` uses `{env:OPENAI_API_KEY}` references that resolve from the shell, not from `auth.json` alone.

### --apply flag (staging → live deployment)

The `--apply` flag copies staging output to live config paths with automatic `.bak` backups:

| Flag | Behavior |
|------|----------|
| (none) | Staging-only — no live files touched |
| `--dry-run` | Generate + validate + checksum verify no mutation |
| `--apply` | Generate + copy staging → live with `.bak` backups |
| `--apply --dry-run` | Generate + validate staging files + show apply plan (no writes) |

**Backup locations:**
- `~/.config/opencode/opencode.jsonc.bak`
- `~/.hermes/config.yaml.bak`
- `~/.local/share/opencode/auth.json.bak`
- `~/.hermes/host-config-gen/export-env.sh` (new file — no backup needed; regenerated each run)

The apply step is an explicit opt-in — the default (no flags) remains staging-only per the safety guarantee.

### Section-Based .env Sync (sync-env.sh)

`sync_env_to_hermes()` in `lib/sync-env.sh` manages a delimited section in `~/.hermes/.env`, replacing only the block controlled by the repo while preserving everything else — Hermes auto-generated entries, user-added keys, and third-party tool configs.

**Marker format:**

```
# >>> hermes-x-opencode-host-config begin >>>
... repo-managed entries ...
# <<< hermes-x-opencode-host-config end <<<
```

**Behavior:**

| Scenario | Action |
|----------|--------|
| Destination `~/.hermes/.env` exists with markers | Replace content between markers with source section |
| Destination exists without markers | Append source section (including markers) |
| Destination does not exist | Create file with source section, set `600` permissions |
| Source `.env` has no markers | Abort with error — markers required |

**Workflow:**

```
Edit .env in repo (source of truth)
       │
       ▼
bash install.sh          →  calls sync_env_to_hermes()
       │
       ▼
~/.hermes/.env managed section updated
       │
       ▼
Hermes picks up new env vars on next session
```

**Verification:**

```bash
# Confirm markers present in both files
grep -cF '# >>> hermes-x-opencode-host-config begin >>>' .env ~/.hermes/.env

# Verify managed section replaced, user entries preserved
grep -A1 'hermes-x-opencode-host-config begin' ~/.hermes/.env
```

Key behaviors:
- **Non-destructive by design.** Hermes writes its own entries (API keys, auto-comments) to `~/.hermes/.env`. The section-based approach prevents `sync_env_to_hermes()` from clobbering them.
- **Source of truth is the repo.** The managed section in the repo's `.env` is the authoritative copy. Changes in the live `~/.hermes/.env` managed section are overwritten on each sync.
- **Idempotent.** Running `sync_env_to_hermes()` multiple times produces the same result — the managed section matches the source, non-managed content is untouched.

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
  "model": "<$OPENCODE_DEFAULT_MODEL>",                  // ← injected from OPENCODE_DEFAULT_MODEL
  "small_model": "<$OPENCODE_DEFAULT_MODEL>",            // ← injected from OPENCODE_DEFAULT_MODEL
  "provider": {
    "opencode": {
      "options": { "apiKey": "{env:OPENCODE_ZEN_API_KEY}" } // ← injected
    },
    "litellm": {
      "options": {
        "apiKey": "{env:OPENAI_API_KEY}",               // ← injected
        "baseURL": "http://localhost:4000"               // ← injected
      },
      "models": {                                        // ← union-merged
        "zai/glm-5.2": { "name": "zai/glm-5.2", "limit": {"context": 1048576, "output": 131072} }
        // ... all discovered models (non-llama_cpp)
      }
    },
    "llama_cpp": {                                       // ← injected (separate provider for llama_cpp/* models)
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "apiKey": "{env:OPENAI_API_KEY}",               // ← injected
        "baseURL": "http://localhost:4000",
        "timeout": 600000,
        "setCacheKey": true
      },
      "models": {                                        // ← llama_cpp/* discovered models
        "qwen3.6-27b-q4_k_m": { "name": "llama_cpp/qwen3.6-27b-q4_k_m", "limit": {"context": 262144, "output": 32768} }
      }
    }
  },
  "permission": { "deny": ["rm", "sudo"] },             // ← preserved
  "plugin": ["my-custom-plugin"],                        // ← preserved
  "agent": {
    "build": { "model": "<$OPENCODE_DEFAULT_MODEL>", "mode": "fast" },  // model overridden, mode preserved
    "plan": { "model": "<$OPENCODE_DEFAULT_MODEL>", "mode": "deep" }    // model overridden, mode preserved
  }
}
```

**Merge policy:**

| Target key | Action | Rationale |
|-----------|--------|-----------|
| `provider.opencode` | Ensure present with `{env:OPENCODE_ZEN_API_KEY}` | Free Zen auth for delegation |
| `model`, `small_model` | Set to `OPENCODE_DEFAULT_MODEL` | Zero paid quota for coding subagents |
| `agent.build.model`, `agent.plan.model` | Override to free Zen model | Defeats paid-model pinning in sub-agents |
| `agent.*` (other fields) | Preserve | Mode, description, etc. survive |
| `provider.litellm.models` | Union-merge discovered models | Existing limits preserved; new models added |
| `provider.llama_cpp` | Ensure present with `@ai-sdk/openai-compatible` npm, same baseURL/credentials as litellm, and own models map for `llama_cpp/*` models | OpenCode requires a separate provider block for `llama_cpp/` prefix — otherwise ProviderModelNotFoundError |
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

The existing `api_key` is carried forward from the live config. Other `custom_providers` entries are preserved.

**Model consistency guarantee:** `model.default` and `model.name` are ALWAYS set to the same value. If `HERMES_DEFAULT_MODEL` is set, both are set to that value. Otherwise, both are set to `OPENAI_DEFAULT_MODEL`. Stale values from the live config are never preserved — this prevents drift where the two fields could silently point to different models.

### Environment-gated config blocks

Beyond the `custom_providers` overlay, `config-hermes.sh` emits optional YAML blocks gated on environment variables. These blocks live in the generated `config-hermes-overlay.yaml` alongside the `custom_providers` entry:

| Env var | Default | Writes to config.yaml | Effect |
|---------|---------|-----------------------|--------|
| `HERMES_YOLO_MODE` | *(off)* | `approvals:\n  mode: off` | Only when set to `"1"`. Skips the manual approval prompt before dangerous shell commands — equivalent to launching Hermes with `--yolo`. |
| `HERMES_DELEGATION_MAX_ITERATIONS` | `50` | `delegation:\n  max_iterations: <N>` | Caps how many iterations a `delegate_task` subagent loop may run. Always present (default 50). |
| `HERMES_DELEGATION_MODEL` | *(unset)* | `delegation:\n  model: <model_id>` | Only when set. Routes subagent conversations to a different model (typically cheaper/faster) than the parent. |
| `HERMES_DELEGATION_PROVIDER` | *(unset)* | `delegation:\n  provider: <provider_name>` | Only when set alongside `HERMES_DELEGATION_MODEL`. Routes subagents to a different provider. If only model is set, subagents inherit the parent's provider. |
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
| `OPENCODE_ZEN_API_KEY` | OpenCode Zen free-tier credential | `~/.hermes/.env` | `env-auth.sh` (read in-process)<br>OpenCode runtime via `{env:OPENCODE_ZEN_API_KEY}` |
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

# Confirm OPENCODE_DEFAULT_MODEL is applied correctly
grep -q "\"model\": \"${OPENCODE_DEFAULT_MODEL}\"" staging/opencode.jsonc
grep -q '"apiKey": "{env:OPENCODE_ZEN_API_KEY}"' staging/opencode.jsonc

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
- `provider.llama_cpp` block is created with `@ai-sdk/openai-compatible` npm, same credentials/baseURL as litellm, and a separate models map for `llama_cpp/*` models
- Hermes overlay carries forward all non-litellm `custom_providers` entries
- Both provider credentials are seeded in staging `auth.json` from `.env` with `config.yaml` fallback

## What Fails

- **Corrupt live JSONC:** If `opencode.jsonc` contains unparseable content, the generator starts from an empty base — all custom blocks are lost in staging.
- **Missing Zen key:** If `OPENCODE_ZEN_API_KEY` is absent from `~/.hermes/.env`, the `opencode` provider in `auth.json` is not seeded — OpenCode Zen auth fails at runtime.
- **Agent sub-block model pin:** If the live config pins a paid model in `agent.build.model` or `agent.plan.model` and the MERGE doesn't override it, the free-mission objective is defeated. The generator explicitly overrides these sub-block models.

## Resolution

- **Corrupt live JSONC:** Run `python3 -m json.tool` on the live config after manually fixing the syntax. The tolerant JSONC parser strips comments; issues are typically trailing commas or unclosed braces.
- **Missing Zen key:** Add `OPENCODE_ZEN_API_KEY=<your-key>` to `~/.hermes/.env`.
- **Agent sub-block model pin:** The generator overrides `agent.build.model` and `agent.plan.model` to the free Zen model. Other agent fields (mode, description) are preserved. If the override fails, check the staging diff in `staging/opencode-merge-summary.txt`.

## Verdict

The MERGE strategy correctly balances model-list refresh with config preservation. The surgical merge targets (provider blocks, model references, credentials) are well-isolated from hand-tuned content. The single-env-var credential pattern (`OPENCODE_ZEN_API_KEY`) directly feeds both `{env:OPENCODE_ZEN_API_KEY}` resolution and the `auth.json` opencode provider.
