# 05 — Cross-Agent Delegation

## What

Cross-agent delegation enables Hermes Agent to dispatch coding tasks to OpenCode CLI (and vice versa), sharing the same LiteLLM model pool while enforcing a zero-paid-quota policy for coding subagents.

## Why

- Hermes Agent provides a rich skill ecosystem, cron scheduling, and multi-agent orchestration. OpenCode CLI provides dedicated plan/build agents optimized for code generation. Each agent has strengths the other lacks.
- Running coding tasks through a paid model burns token quota unnecessarily when free Zen models are available. The delegation architecture ensures Hermes→OpenCode coding tasks always use the free tier.
- Both agents share the same LiteLLM proxy, ensuring consistent model availability. If a model works in one agent, it works in the other.

## How

### Delegation matrix

```
┌──────────────────────────────────────────────────────────────────┐
│                        LiteLLM Proxy (:4000)                     │
│              zai/glm-5.2  │  deepseek-v4  │  gpt-5  │  ...       │
└──────────────┬────────────────────────────┬──────────────────────┘
               │                            │
               ▼                            ▼
    ┌──────────────────┐        ┌──────────────────────────┐
    │   Hermes Agent    │        │     OpenCode CLI          │
    │   (orchestrator)  │        │     (coding executor)     │
    │                   │        │                           │
    │ skill: opencode   │───────►│ model: deepseek-v4-       │
    │   └─► opencode run│        │        flash-free (FREE)  │
    │                   │        │                           │
    │                   │◄───────│ terminal tool: hermes     │
    │                   │        │   └─► query via LiteLLM   │
    └──────────────────┘        └──────────────────────────┘
```

### Hermes → OpenCode delegation

Hermes delegates coding tasks via the `opencode` skill. The skill invokes `opencode run` with the free Zen model:

```bash
# Inside the opencode skill definition
opencode run --model opencode/deepseek-v4-flash-free \
  --agent plan -s "$SESSION_ID" \
  "Implement the fix for issue #42"
```

The free model is enforced at two levels:

1. **Config level:** `provider.opencode` with `{env:OPENCODE_API_KEY}` is injected into `opencode.jsonc` by the config generator.
2. **Top-level model pin:** `model` and `small_model` are set to `opencode/deepseek-v4-flash-free`, ensuring all OpenCode sessions default to the free tier.

### OpenCode → Hermes delegation

OpenCode can query Hermes Agent via the `hermes` terminal tool, which calls the LiteLLM proxy through Hermes' configured model:

```jsonc
// In opencode.jsonc — hermes terminal tool definition
{
  "terminal": {
    "tools": {
      "hermes": {
        "command": "hermes ask",
        "description": "Query Hermes Agent for non-coding tasks"
      }
    }
  }
}
```

When OpenCode needs capabilities outside its scope (web search, browser automation, cron scheduling), it shells out to `hermes`, which processes the request through the LiteLLM proxy using its configured `OPENAI_DEFAULT_MODEL` (`zai/glm-5.2` — paid).

### Model selection for delegation

| Delegation direction | Model | Provider | Cost | Rationale |
|---------------------|-------|----------|------|-----------|
| Hermes → OpenCode (coding) | `opencode/deepseek-v4-flash-free` | opencode (Zen) | FREE | Coding is high-token; free tier saves quota |
| Hermes → OpenCode (planning) | `opencode/deepseek-v4-flash-free` | opencode (Zen) | FREE | Plan agents also benefit from free tier |
| OpenCode → Hermes (non-coding) | `zai/glm-5.2` (Hermes default) | litellm (proxy) | Paid | Non-coding tasks use Hermes' configured model |
| Hermes (direct use) | `zai/glm-5.2` | litellm (proxy) | Paid | Orchestrator needs reliable, capable model |

### Fallback chain

```
OPENCODE_FALLBACK_MODEL env var (comma-separated)
        │
        ▼
opencode-fallback.jsonc (plugin config)
        │
        ▼
opencode-runtime-fallback plugin
        │
        ▼
Iterates fallback models in order until one succeeds
```

The fallback chain activates when the primary Zen model is unavailable. Models are tried in order; the first successful response wins.

### Credential flow

```
~/.hermes/.env
├── OPENCODE_ZEN_API_KEY=<zen-key>        ──► env-auth.sh reads in-process
└── OPENAI_API_KEY=<proxy-key>             ──► env-auth.sh reads in-process
         │
         ▼
staging/auth.json                          ──► user applies to ~/.local/share/opencode/auth.json
         │
         ▼
opencode.jsonc {env:OPENCODE_API_KEY}      ──► resolves at OpenCode runtime
opencode.jsonc {env:OPENAI_API_KEY}        ──► resolves at OpenCode runtime
```

## Verification

```bash
# Test Hermes → OpenCode delegation (requires opencode CLI)
opencode run --model opencode/deepseek-v4-flash-free -q "say hello" 2>&1

# Verify the free Zen model is configured
grep '"model": "opencode/deepseek-v4-flash-free"' ~/.hermes/host-config-gen/staging/opencode.jsonc

# Verify provider.opencode has {env:OPENCODE_API_KEY}
grep '"apiKey": "{env:OPENCODE_API_KEY}"' ~/.hermes/host-config-gen/staging/opencode.jsonc

# Test OpenCode → Hermes delegation (from within opencode session)
# Run from opencode: hermes ask "what time is it?"

# Verify fallback chain configuration
echo "OPENCODE_FALLBACK_MODEL=opencode/deepseek-v4-flash-free,litellm/zai/glm-5.2"

# Confirm Zen auth resolves
python3 -c "
import os, re
env_file = os.path.expanduser('~/.hermes/.env')
with open(env_file) as f:
    for line in f:
        m = re.match(r'^OPENCODE_ZEN_API_KEY=(.*)$', line.strip())
        if m:
            print('Zen key found (length: {})'.format(len(m.group(1).strip('\"\\''))))
            break
    else:
        print('Zen key NOT FOUND')
"
```

## What Works

- Hermes delegates coding tasks to OpenCode via the `opencode` skill using `opencode run`
- OpenCode defaults to the free Zen model for both `model` and `small_model`
- Agent sub-block models (build, plan) are also pinned to the free Zen model
- Both provider credentials are staged in `auth.json` and resolve via `{env:VAR}` references
- The `OPENCODE_FALLBACK_MODEL` chain provides ordered fallback if the primary Zen model is unavailable

## What Fails

- **Zen auth failure (EC3):** If `OPENCODE_API_KEY` is not exported or differs from `OPENCODE_ZEN_API_KEY`, the `{env:OPENCODE_API_KEY}` reference in `opencode.jsonc` resolves to empty or wrong value. OpenCode cannot authenticate with the Zen provider.
- **OpenCode not installed:** The `opencode` skill's `opencode run` command fails silently. Hermes cannot delegate coding tasks.
- **Model mismatch in sub-agents:** If `agent.build.model` or `agent.plan.model` is not overridden to the free Zen model, sub-agents run on the paid model pinned in the live config, defeating the cost-saving objective.

## Resolution

- **Zen auth failure:** Export `OPENCODE_API_KEY` with the same value as `OPENCODE_ZEN_API_KEY`. Add `OPENCODE_API_KEY=<your-zen-key>` to `~/.hermes/.env`. Both keys must have identical values.
- **OpenCode not installed:** Install OpenCode CLI via `npm install -g opencode-ai` or the project's install script. The `install.sh` prerequisite check warns if `opencode` is missing.
- **Model mismatch in sub-agents:** The config generator explicitly overrides `agent.build.model` and `agent.plan.model` to `opencode/deepseek-v4-flash-free`. Verify the override with `grep -A2 '"build"' staging/opencode.jsonc`.

## Verdict

The delegation architecture achieves the dual objective of (1) leveraging each agent's strengths and (2) eliminating paid token burn for coding subagents. The two-env-var credential pattern is a friction point but is necessary due to OpenCode's `{env:VAR}` resolution mechanism. The fallback chain provides resilience when the free Zen model is unavailable.
