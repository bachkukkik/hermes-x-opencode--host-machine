# PRD: Hermes × OpenCode Host Config Generator

## 1. Summary

A bare-metal config generator that clones the Docker stack's config-generation pipeline for host-level installation. Discovers models from a LiteLLM proxy, produces merged config overlays for Hermes Agent and OpenCode CLI, and seeds credential stores — all without touching live config files.

## 2. Contacts

| Role | Name | Comment |
|------|------|---------|
| Author | bachkukkik | Architect, maintainer |
| Reference | hermes-x-opencode | Docker stack (upstream model) |

## 3. Background

The hermes-x-opencode Docker stack auto-generates `config.yaml` and `opencode.jsonc` inside a container at boot. A bare-metal host running Hermes Agent and OpenCode CLI natively needs the same model-discovery and config-generation logic, but without the container runtime, service management, or `su` user-switching.

This repo extracts just the config-generation pipeline, adapted for host paths (`$HOME/.hermes/`, `$HOME/.config/opencode/`), with a critical safety guarantee: **the generator writes only to a staging directory**. The user reviews diffs and applies manually.

### Related Repository

The parent project (Docker stack with full container orchestration, entrypoints, services, and build scripts) lives at [hermes-x-opencode](https://github.com/bachkukkik/hermes-x-opencode). The two repos are independent — linked by README cross-reference only.

## 4. Objective

**Goal:** Provide host-level config generation that is functionally equivalent to the Docker stack's model-discovery + config-generation pipeline.

**Key Results:**
- KR1: `generate.sh --dry-run` produces valid staging output matching Docker stack semantics
- KR2: All discovered chat models from LiteLLM appear in both OpenCode and Hermes configs
- KR3: OpenCode defaults to FREE Zen model (`opencode/deepseek-v4-flash-free`) — zero paid quota for Hermes→OpenCode delegation
- KR4: Existing hand-tuned config is preserved (MERGE mode, not overwrite)
- KR5: No live config files are ever mutated — staging-only guarantee verified by checksum snapshot
- KR6: Cross-agent delegation works across all agent platforms (Hermes→OpenCode, OpenCode→Hermes)

## 5. Market Segment

**For:** Self-hosted Hermes Agent users running on bare-metal Linux who also use OpenCode CLI for coding delegation. They already have a LiteLLM proxy and want automatic model discovery + config refresh without a Docker stack.

**Constraints:**
- Must run with `bash` + `python3` + `python3-yaml` only — no Node.js, no Docker, no systemd
- OpenAI-compatible endpoint may be on localhost or remote — configurable via `OPENAI_BASE_URL`
- Existing `opencode.jsonc` has hand-tuned permission blocks, plugins, and agent sub-blocks that MUST survive

## 6. Value Proposition

- **Zero-touch safety:** Staging output only — review before apply — checksum snapshot proves no live mutation
- **MERGE mode:** New models added without clobbering existing hand-tuned config
- **Free delegation:** OpenCode defaults to Zen free tier — no paid token burn for coding subagents
- **Key safety:** API keys read in-process via Python — never exposed as shell variables (avoids agent shell redaction)

## 7. Solution

### 7.1 Architecture

```
~/.hermes/host-config-gen/
├── generate.sh                    # Main orchestrator
├── README.md                      # User docs
├── lib/
│   ├── constants.sh               # Host paths + defaults
│   ├── model-discovery.sh         # LiteLLM /v1/models → filtered list
│   ├── config-opencode.sh         # opencode.jsonc MERGE generator
│   ├── config-hermes.sh           # Hermes config overlay generator
│   └── env-auth.sh                # Credential resolution + auth.json staging
└── staging/                       # Output (gitignored)
    ├── opencode.jsonc             # Merged OpenCode config
    ├── config-hermes-overlay.yaml # Merged Hermes config
    ├── auth.json                  # OpenCode credential store
    ├── discovered-models.txt      # Raw model list
    └── opencode-merge-summary.txt # Diff summary
```

### 7.2 Key Features

1. **Model Discovery** — Queries `OPENAI_BASE_URL/v1/models`, filters non-chat models (embed, whisper, tts, dall-e, sora, image, realtime, transcrib, moderat, audio, codegen, babbage, davinci, curie, ada, text-, stable, midjourney, flux, /sd/, mj, replicate, resolution, wildcard), dedupes, and seeds a default model (zai/glm-5.2)

2. **OpenCode Config Merge** — Deep-merges into existing `opencode.jsonc`:
   - provider.opencode with `{env:OPENCODE_API_KEY}` (free Zen)
   - provider.litellm with refreshed models map
   - top-level model + small_model + agent.build/plan.model → FREE Zen model
   - Preserves: permission, plugin, server, experimental, agent mode/description blocks

3. **Hermes Config Overlay** — Form B custom_providers with static models map:
   - Fine-grained context lengths per model family
   - Empty `{}` mappings for unknowns (agent self-resolves)
   - Skills external_dirs, approvals, goals, delegation blocks (env-gated)

4. **Fallback Chain** — `OPENCODE_FALLBACK_MODEL` supports comma-separated ordered fallback models; generates `opencode-fallback.jsonc` for the opencode-runtime-fallback plugin

5. **Model Consistency** — `model.default` and `model.name` in the Hermes overlay are always set to the same value: either `HERMES_DEFAULT_MODEL` (if set) or `OPENAI_DEFAULT_MODEL` (fallback). Stale values from the live config are never preserved, preventing silent model drift.

6. **Credential Staging** — Seeds `auth.json` with both opencode (Zen) and litellm (proxy) keys

### 7.3 Model Selection Defaults

| App | Default Model | Provider | Cost |
|-----|---------------|----------|------|
| OpenCode (main) | opencode/deepseek-v4-flash-free | opencode (Zen) | FREE |
| OpenCode (small) | opencode/deepseek-v4-flash-free | opencode (Zen) | FREE |
| OpenCode (agent.build) | opencode/deepseek-v4-flash-free | opencode (Zen) | FREE |
| OpenCode (agent.plan) | opencode/deepseek-v4-flash-free | opencode (Zen) | FREE |
| Hermes (default) | zai/glm-5.2 | litellm (proxy) | Paid |

### 7.4 Cross-Agent Delegation

- Hermes → OpenCode: via `opencode` skill → `opencode run` → uses free Zen model
- OpenCode → Hermes: via `hermes` terminal tool → uses LiteLLM proxy through configured model
- Both agents share the same LiteLLM model list, ensuring consistent model availability

### 7.5 Assumptions

- OpenAI-compatible endpoint is reachable at `http://localhost:4000` (or `OPENAI_BASE_URL`)
- `~/.hermes/config.yaml` exists with valid `api_key` for the proxy
- `~/.hermes/.env` exists with `OPENCODE_API_KEY`
- `~/.config/opencode/opencode.jsonc` exists (or will be created from scratch if absent)
- `python3-yaml` is installed (`pip install pyyaml`)

## 8. Release

**Phase 1 (current):** Core config generation — model discovery, OpenCode MERGE, Hermes overlay
**Phase 2 (next):** Documentation parity — docs/ with architecture deep-dives, tests/ with bats e2e
**Phase 3:** Knowledge layer — graphify knowledge graph, llm-wiki durable documentation
**Phase 4:** CI/CD — GitHub Actions e2e test pipeline

### Verification Policy

Every change must pass:
1. `bash -n` on all `.sh` scripts
2. `python3 -m json.tool` on staging/opencode.jsonc
3. `python3 -c "import yaml; yaml.safe_load(...)"` on staging/config-hermes-overlay.yaml
4. `generate.sh --dry-run` exit code 0
5. Live file checksum snapshot proves zero mutation
6. `bats tests/` all pass
