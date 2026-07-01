# Hermes × OpenCode Host Config Generator — Agent Instructions

This repo builds a bare-metal config generator that clones the Docker stack's model-discovery and config-generation pipeline for host-level installation. Discovers models from a LiteLLM proxy, produces merged config overlays for Hermes Agent and OpenCode CLI, and seeds credential stores — all without touching live config files.

## Architecture

```
Host machine (~/.hermes/host-config-gen/)
├── generate.sh              # Main orchestrator
├── install.sh               # Deploy to ~/.hermes/host-config-gen/
├── README.md                # User docs
├── lib/
│   ├── constants.sh         # Host paths + defaults
│   ├── model-discovery.sh   # LiteLLM /v1/models → filtered list
│   ├── config-opencode.sh   # opencode.jsonc MERGE generator
│   ├── config-hermes.sh     # Hermes config overlay generator
│   └── env-auth.sh          # Credential resolution + auth.json staging
└── staging/                 # Output (gitignored)
    ├── opencode.jsonc               # Merged OpenCode config
    ├── config-hermes-overlay.yaml   # Merged Hermes config
    ├── auth.json                    # OpenCode credential store
    ├── discovered-models.txt        # Raw model list
    └── opencode-merge-summary.txt   # Diff summary
```

**Relationship:** This repo is a standalone extraction from [hermes-x-opencode](https://github.com/bachkukkik/hermes-x-opencode) (Docker stack). The two repos are independent — linked by README cross-reference only. The Docker stack has full container orchestration, entrypoints, services, and build scripts; this repo has only the config-generation pipeline, adapted for host paths.

See `PRD.md` for full specifications.

---

## Standing Orders (ALWAYS apply)

These rules apply to **every session, every agent, every prompt** — no exceptions.

### 1. MANDATED SKILLS

Load and use these skills on EVERY task:

| Skill | When | Purpose |
|-------|------|---------|
| `karpathy-guidelines` | ALWAYS | Research context, knowledge base patterns, clean code |
| `security-best-practices` | ALWAYS | All code changes must follow security best practices |
| `coding-agents-docs-guideline` | Docs | Document all changes in the repo |
| `yeet` | Git ops | All commit/push/branch operations |
| `opencode-plan-build-orchestrator` | Coding via kanban/delegate | All coding tasks MUST route through this skill's plan→build→verify pipeline. Loaded by the orchestrator for decomposition rules AND passed via `skills=[...]` to every kanban worker / delegate_task subagent that writes code. |

### 2. Kanban Delegation Rules (coding discipline)

- **Every kanban card that involves code changes MUST include `skills=["opencode-plan-build-orchestrator", "karpathy-guidelines"]`** in the `kanban_create` call. Without this the worker sees only KANBAN_GUIDANCE (lifecycle, no coding discipline) and edits code directly instead of routing through plan→build→verify.
- **Every `delegate_task` call for coding work MUST include `"opencode-plan-build-orchestrator"` and `"karpathy-guidelines"`** in the subagent's goal context (e.g., "load opencode-plan-build-orchestrator and karpathy-guidelines; follow the 6-phase pipeline"). The orchestrator parent NEVER writes repo-tracked files directly — all code edits go to subagents.
- If you forget this, the worker's first instinct will be to `patch`/`write_file` directly and the plan→build→verify pipeline is bypassed.

### 3. Code Quality Rules

- **No hardcoded secrets** — use env vars or in-process python3 key reads
- **Key safety (EC2):** All API key reads happen IN-PROCESS via python3 — keys never round-trip through shell variables. Hermes secret-redaction mangles keys interpolated into the agent shell, so `grep`/`sed`/`awk` extraction is forbidden. Every lib file (model-discovery.sh, env-auth.sh, config-hermes.sh) reads config.yaml and .env via python heredocs.
- **`bash -n`** on all `.sh` scripts — every change must pass syntax check
- **No `shell=True`** in any python subprocess calls
- **Staging-only guarantee:** The generator NEVER touches live config files (`~/.hermes/config.yaml`, `~/.config/opencode/opencode.jsonc`, `~/.local/share/opencode/auth.json`). All output goes to `~/.hermes/host-config-gen/staging/`. Dry-run verifies this via sha256 checksum snapshot.
- **MERGE mode, never overwrite:** Existing hand-tuned config blocks (permission deny-lists, plugin arrays, agent mode/description, server, experimental) are deep-merged — only target keys (provider blocks, model fields, models map) are updated. The user reviews staging diffs and applies manually.
- **EC2 key safety pattern:** python3 heredocs with `PYEOF` delimiter, reading keys from `~/.hermes/config.yaml` and `~/.hermes/.env` inside the same python process that performs HTTP requests — the secret never exists in a shell variable.

### 4. Verification Commands

After any change to lib scripts or generate.sh:

```bash
# Syntax check all shell scripts
for s in generate.sh install.sh lib/*.sh; do bash -n "$s"; done

# Dry-run generator (includes validation + live-file checksum proof)
bash generate.sh --dry-run

# Validate staging JSON
python3 -m json.tool staging/opencode.jsonc

# Validate staging YAML
python3 -c "import yaml; yaml.safe_load(open('staging/config-hermes-overlay.yaml'))"

# Run bats test suite (when present)
bats tests/
```

### 5. File Locations (host paths)

| Path | Purpose |
|------|---------|
| `~/.hermes/config.yaml` | Hermes Agent config (LIVE — read, never written by generator) |
| `~/.hermes/.env` | Hermes environment secrets (LIVE — read, never written) |
| `~/.hermes/host-config-gen/` | Generator installation + staging root |
| `~/.hermes/host-config-gen/generate.sh` | Main orchestrator |
| `~/.hermes/host-config-gen/lib/` | Shell library modules |
| `~/.hermes/host-config-gen/staging/` | Output directory (gitignored — review before apply) |
| `~/.config/opencode/opencode.jsonc` | OpenCode config (LIVE — read, MERGE source) |
| `~/.local/share/opencode/auth.json` | OpenCode credential store (LIVE — read, seed target) |

### 6. LiteLLM / Model Discovery

- **Endpoint:** `$OPENAI_BASE_URL/v1/models` (default `http://localhost:4000`)
- **Filter pipeline:** Drops non-chat models: embed, whisper, tts, dall-e, sora, image, realtime, transcrib, moderat, audio, codegen, babbage, davinci, curie, ada, text-, stable, midjourney, flux, /sd/, mj, replicate, resolution, and wildcard patterns ending with `/*`
- **Fallback:** When LiteLLM is unreachable or returns empty, seeds `zai/glm-5.2` as `OPENAI_DEFAULT_MODEL` (EC1)
- **Per-model provider routing:** `config-opencode.sh` determines `opencode/` vs `litellm/` prefix independently per model. The free Zen model (`opencode/deepseek-v4-flash-free`) routes through the `opencode` provider; all discovered LiteLLM models route through the `litellm` provider.

### 7. Project-Specific Patterns

- **MERGE mode preservation:** The `config-opencode.sh` deep-merge preserves ALL non-target keys in `opencode.jsonc` — permission blocks, plugin arrays, agent sub-blocks (mode, description), server config, experimental. Only `provider.opencode`, `provider.litellm.models`, top-level `model`/`small_model`, and `agent.build.model`/`agent.plan.model` are touched.
- **Hermes Form B schema:** The Hermes overlay uses Form B custom_providers with a static `models:` map (`{model_id: {context_length: N}}`) listing all discovered models. Context lengths are computed via heuristics per model family. Unknown models get empty `{}` mappings (agent self-resolves). The existing inline `api_key` is carried forward in-process.
- **EC2 (key safety) pattern — critical:** Every lib file that touches secrets uses `python3 - "$config_path" "$other_arg" << 'PYEOF'` — the python process opens config.yaml/.env directly, reads the key into a python variable, and performs the HTTP call or transform inside the same process. NEVER use `grep`/`sed`/`awk`/`jq` on config.yaml or `.env` to extract keys.
- **Bash heredoc JSON breaks with 300+ dynamic entries** — use `python3 -c "import json; json.dump(...)"` for config generation
- **Free Zen model requirement:** OpenCode must default to `opencode/deepseek-v4-flash-free` so that Hermes→OpenCode delegation burns no paid token quota. The credential `OPENCODE_ZEN_API_KEY` is read from `~/.hermes/.env` and used directly as the `{env:OPENCODE_ZEN_API_KEY}` value in the opencode provider block.
- **Fallback chain:** `OPENCODE_FALLBACK_MODEL` supports comma-separated ordered fallback models. Generates `opencode-fallback.jsonc` for the `opencode-runtime-fallback` plugin.
- **Cross-agent delegation:** Hermes→OpenCode via `opencode` skill uses free Zen model; OpenCode→Hermes via `hermes` terminal tool uses LiteLLM proxy through configured model. Both agents share the same discovered model list for consistent availability.

### 8. Agent Capabilities

| Capability | Details |
|------------|---------|
| **graphify** | Run `/graphify` to build a knowledge graph from repo contents. Output goes to `graphify-out/`. Phase 3 milestone. |
| **llm-wiki** | Personal knowledge base at `~/wiki/` (host path, not container). Auto-initialized with SCHEMA.md, index.md, log.md backbone. Agent ingests sources into `raw/articles/` and creates entity/concept pages with `[[wikilinks]]`. Phase 3 milestone. |

---

## Release Phases

| Phase | Status | Content |
|-------|--------|---------|
| Phase 1 | Current | Core config generation — model discovery, OpenCode MERGE, Hermes overlay |
| Phase 2 | Next | Documentation parity — docs/ with architecture deep-dives, tests/ with bats e2e |
| Phase 3 | Planned | Knowledge layer — graphify knowledge graph, llm-wiki durable documentation |
| Phase 4 | Planned | CI/CD — GitHub Actions e2e test pipeline |
