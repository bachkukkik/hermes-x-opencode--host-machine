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
   - provider.opencode with `{env:OPENCODE_ZEN_API_KEY}` (free Zen)
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
- `~/.hermes/.env` exists with `OPENCODE_ZEN_API_KEY`
- `~/.config/opencode/opencode.jsonc` exists (or will be created from scratch if absent)
- `python3-yaml` is installed (`pip install pyyaml`)

## 8. Release

**Phase 1 (completed ✓):** Core config generation — model discovery, OpenCode MERGE, Hermes overlay
**Phase 2 (completed ✓):** Documentation parity — docs/ with architecture deep-dives, tests/ with bats e2e
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

## 9. Cross-Repo Gap Bridge (host ← Docker reference)

### 9.1 Gap Inventory

This section tracks gaps between the host config generator (this repo) and the reference
Docker stack ([hermes-x-opencode](https://github.com/bachkukkik/hermes-x-opencode)).
Gaps are classified as:

- **PORT** — feature present in reference, missing in host → must be ported
- **SKIP** — Docker-specific concept, N/A for host (service lifecycle, Dockerfile, compose)
- **ALREADY-PRESENT** — feature exists in both (verified)

### 9.2 Feature Parity Matrix

| Feature | Reference PR | Host Status | Action |
|---------|-------------|-------------|--------|
| OPENCODE_ZEN_API_KEY → OPENCODE_ZEN_API_KEY rename | #68 | ALREADY-PRESENT | PORTED ✓ |
| Per-delegation model routing (HERMES_DELEGATION_MODEL/PROVIDER) | #68 | ALREADY-PRESENT | PORTED ✓ |
| Quantized GGUF ctx pin (*qwen3.6-27b*q4* → 262144) | #66 | ALREADY-PRESENT | verified |
| HERMES_COMPRESSION_THRESHOLD transport | #66 | ALREADY-PRESENT | verified |
| auth.json OR guard contract comment | #66 | ALREADY-PRESENT | PORTED ✓ |
| .env.example alignment with reference naming | #68 | ALREADY-PRESENT | PORTED ✓ |
| DELEGATION_MODEL test (AC34 equivalent) | #68 | ALREADY-PRESENT | PORTED ✓ |
| Ctx pin + credential resolution tests | #66 | ALREADY-PRESENT | PORTED ✓ |
| Dockerfile/build pipeline | — | SKIP (Docker-only) | SKIP |
| docker-compose.yml | — | SKIP (Docker-only) | SKIP |
| Entrypoint/service lifecycle | — | SKIP (Docker-only) | SKIP |
| Profile/dojoctrine (righthand-man) | #62-#65 | SKIP (Docker-only) | SKIP |
| Browser human loop | #58,#64 | SKIP (Docker-only) | SKIP |
| Dashboard service | #57 | SKIP (Docker-only) | SKIP |
| Wiki init (container path) | #64 | SKIP (Docker-only) | SKIP |
| Skill installation (Docker build-time) | #67 | SKIP (Docker-only) | SKIP |

### 9.3 Port Details: OPENCODE_ZEN_API_KEY (from PR #68) — PORTED ✓

**Scope:** Rename `OPENCODE_API_KEY` (unqualified) → `OPENCODE_ZEN_API_KEY` (with ZEN qualifier)
across all host files to align with official Hermes agent convention (hermes config, hermes doctor,
opencode-zen provider plugin).

**Changes:**
- `.env.example`: rename `OPENCODE_API_KEY` → `OPENCODE_ZEN_API_KEY`, update comment
- `lib/config-opencode.sh`: `{env:OPENCODE_API_KEY}` → `{env:OPENCODE_ZEN_API_KEY}` (2 references)
- `lib/env-auth.sh`: read `OPENCODE_ZEN_API_KEY` from .env; update summary text
- `lib/constants.sh`: update any default/fallback references
- `docs/`: update all references
- `tests/`: update all test assertions

**Success criteria:**
- `generate.sh --dry-run` produces staging with `{env:OPENCODE_ZEN_API_KEY}` in opencode.jsonc
- auth.json seeds opencode provider from `OPENCODE_ZEN_API_KEY` env var
- All bats tests pass with new naming
- Zero references to old unqualified `OPENCODE_API_KEY` remain (grep check)

### 9.4 Port Details: Per-Delegation Model Routing (from PR #68) — PORTED ✓

**Scope:** Add `HERMES_DELEGATION_MODEL` and `HERMES_DELEGATION_PROVIDER` env vars that
conditionally write `delegation.model` and `delegation.provider` under the `delegation:` block
in the Hermes config overlay, enabling different models for parent vs subagent conversations.

**Status:** Already implemented — `lib/config-hermes.sh` contains HERMES_DELEGATION_MODEL + PROVIDER logic.

**Changes:**
- `.env.example`: add `HERMES_DELEGATION_MODEL` and `HERMES_DELEGATION_PROVIDER` (commented)
- `lib/config-hermes.sh`: after `delegation.max_iterations`, conditionally add `model` and `provider` fields when env vars are set

**Success criteria:**
- When `HERMES_DELEGATION_MODEL=openai/gpt-4o-mini` is set, staging overlay contains `delegation.model: openai/gpt-4o-mini`
- When `HERMES_DELEGATION_PROVIDER=litellm` is set, staging overlay contains `delegation.provider: litellm`
- When unset, delegation block only contains `max_iterations` (no model/provider fields)

### 9.5 Port Details: auth.json OR Guard Contract (from PR #66) — PORTED ✓

**Scope:** Add contract comment to `lib/env-auth.sh` documenting the OR logic: litellm credential
seeds from OPENAI_API_KEY, which falls back to config.yaml inline key. The OR guard prevents
regression where both opencode and litellm providers are silently empty.

**Status:** Already implemented — `lib/env-auth.sh` contains the OR guard contract comment.

**Changes:**
- `lib/env-auth.sh`: add contract comment above auth.json building section

### 9.6 Test Additions — PORTED ✓

**Status:** Already implemented — test files exist under `tests/e2e/`.

| Test file | Tests | Maps to |
|-----------|-------|---------|
| `tests/e2e/20-zen-api-key.bats` | AC34: OPENCODE_ZEN_API_KEY in opencode.jsonc + auth.json | PR #68 |
| `tests/e2e/21-delegation-model.bats` | AC35: delegation.model/provider in staging overlay | PR #68 |
| `tests/e2e/22-ctx-pin-and-credentials.bats` | CTX1-3: quantized GGUF ctx pin, CRED1-2: auth.json OR guard | PR #66 |

### 9.7 Documentation Updates — PORTED ✓

**Status:** Already implemented — docs updated to reflect new features.

| Doc | Update |
|-----|--------|
| `docs/02-config-generation.md` | Update OPENCODE_ZEN_API_KEY naming, add delegation model routing section |
| `docs/03-model-discovery.md` | Add quantized GGUF ctx pin subsection |
| `docs/06-verification.md` | Add credential resolution docs paragraph |

## 10. Documentation and Testing Gaps

### 10.1 Missing Docs (Phase 2 items)

All existing docs/ files are present. Gaps are content-level updates needed to match new features
(Section 9.7 above) plus structural completeness against the codebase.

### 10.2 Test Coverage (Phase 2 items)

All Phase 2 tests are present and passing:
- `tests/e2e/01-install.bats` — install.sh deployment + prerequisite checks
- `tests/e2e/02-generate.bats` — generate.sh output + exit codes
- `tests/e2e/03-config-validity.bats` — JSON/YAML validity, model fields, resolve_ctx_len, env-gated blocks
- `tests/e2e/04-model-discovery.bats` — model fetch, filter, wildcard, EC1 fallback
- `tests/e2e/05-merge-safety.bats` — MERGE mode preservation, dry-run checksum safety
- `tests/e2e/06-fallback-chain.bats` — fallback chain generation + formatting
- `tests/e2e/20-zen-api-key.bats` — AC34: OPENCODE_ZEN_API_KEY in opencode.jsonc + auth.json
- `tests/e2e/21-delegation-model.bats` — AC35: delegation.model/provider in staging overlay
- `tests/e2e/22-ctx-pin-and-credentials.bats` — CTX1-3: quantized GGUF ctx pin, CRED1-3: auth.json OR guard

### 10.3 Knowledge Layer (Phase 3 items)

- `graphify-out/` needs regeneration after code changes
- `llm-wiki` at `~/wiki/` needs wiki pages for this project

## 11. Multi-Provider Model Routing (Phase 1.5 — bridge gap)

### 11.1 Problem

The current host generator was designed around a Zen-first assumption: OpenCode defaults to
`opencode/deepseek-v4-flash-free` (free tier) to avoid burning paid quota on delegation.
However, the user's actual `.env` shows:

```
OPENCODE_DEFAULT_MODEL=llama_cpp/qwen3.6-27b-q4_k_m       # Local llama.cpp model
OPENCODE_SMALL_MODEL=opencode/deepseek-v4-flash-free        # Zen free tier
OPENCODE_FALLBACK_MODEL=llama_cpp/qwen3.6-27b-q4_k_m        # Local fallback
HERMES_DEFAULT_MODEL=deepseek/deepseek-v4-pro               # Paid proxy model
OPENAI_DEFAULT_MODEL=llama_cpp/qwen3.6-27b-q4_k_m           # Local default
```

The user freely mixes providers: `opencode/` (Zen), `litellm/` (proxy), `llama_cpp/` (local),
and bare model IDs. The generator must handle ALL combinations without assuming any default.

### 11.2 Requirements

| ID | Requirement | Source |
|----|-------------|--------|
| MR-1 | `OPENCODE_DEFAULT_MODEL` may be ANY provider prefix (opencode/litellm/llama_cpp/bare) | User .env |
| MR-2 | `OPENCODE_SMALL_MODEL` may be ANY provider prefix, independent of default | User .env |
| MR-3 | `OPENCODE_FALLBACK_MODEL` comma-separated chain, each entry independently resolved | Upstream #59 |
| MR-4 | Provider resolution must be consistent: same prefix rules for default, small, fallback, agent sub-models | Upstream config-opencode.sh `_resolve_provider_prefix` |
| MR-5 | When default model is non-Zen (e.g. llama_cpp/*), agent.build/plan model must still route correctly | User intent |
| MR-6 | No "Zen-first" bias in docs or comments — treat all providers equally | User intent |
| MR-7 | Existing uncommitted changes (string-aware JSONC parser, env isolation, dynamic preserved blocks) must be committed | Git status |

### 11.3 Gap Matrix (Intended vs Implemented)

| Gap ID | Intended (upstream/doc) | Implemented (host) | Impact | Severity |
|--------|------------------------|-------------------|--------|----------|
| G-01 | Upstream `_strip_provider_prefix` on default+small model | Host sets `existing["model"] = default_model` without stripping | If user sets `OPENCODE_DEFAULT_MODEL=llama_cpp/qwen3.6-27b`, top-level model gets double-prefix `llama_cpp/llama_cpp/...` in provider block — **actually safe** because the host writes the raw model ID (already prefixed) directly to the top-level field, and the provider routing resolves it. NO bug here — the host's approach is simpler and correct. | Low (cosmetic) |
| G-02 | Upstream resolves provider prefix PER model (default, small, fallback) independently | Host resolves fallback per-entry but treats default model as-is | When `OPENCODE_DEFAULT_MODEL=opencode/deepseek-v4-flash-free`, host writes this directly — correct. When `llama_cpp/...`, host also writes directly — correct. **No gap** for top-level model fields. | None |
| G-03 | Upstream `generate_opencode_config` writes direct config (OVERWRITE mode) | Host `generate_opencode_staging` MERGE mode | Architectural difference by design (staging-only safety). No gap to bridge. | None |
| G-04 | Upstream `.env.example` documents multi-provider fallback chains with examples | Host `.env.example` shows only single-model fallback | User cannot discover the multi-model fallback feature | Medium |
| G-05 | Upstream config-opencode.sh has `_strip_provider_prefix` + `_resolve_provider_prefix` for model fields | Host lacks explicit strip/resolve for `OPENCODE_DEFAULT_MODEL` in `model`/`small_model` fields | The host writes raw prefixed model IDs directly, which works because OpenCode reads the prefix from the model string. **No functional bug** — but the upstream's explicit resolution is safer for edge cases. | Low |
| G-06 | Upstream `OPENCODE_SECURITY_MODE` env var controls permission blocks | Host has no security mode concept (staging-only, doesn't generate permission blocks) | N/A for host (host uses MERGE mode, preserves existing permission block) | None |
| G-07 | Upstream seeds auth.json for both user and root | Host stages auth.json only | By design (host never writes to live paths). No gap. | None |
| G-08 | Uncommitted changes in PRD/generate.sh/config-opencode.sh/common.bash not committed | Working tree dirty | Code review/PR cannot proceed | High |

### 11.4 Acceptance Criteria

| AC# | Criteria | Verification |
|-----|----------|--------------|
| AC40 | `OPENCODE_DEFAULT_MODEL=llama_cpp/qwen3.6-27b-q4_k_m` produces valid opencode.jsonc with correct top-level model field | `grep '"model"' staging/opencode.jsonc` |
| AC41 | `OPENCODE_DEFAULT_MODEL=opencode/deepseek-v4-flash-free` produces correct Zen routing | Same grep |
| AC42 | `OPENCODE_DEFAULT_MODEL=litellm/deepseek/deepseek-v4-pro` routes through litellm provider | Check provider block presence |
| AC43 | `OPENCODE_SMALL_MODEL` independent of `OPENCODE_DEFAULT_MODEL` — both can differ | Set both to different providers, verify both fields |
| AC44 | `OPENCODE_FALLBACK_MODEL=z.ai/glm-5.2,llama_cpp/qwen3.6-27b` produces correct multi-provider chain | Check opencode-fallback.jsonc |
| AC45 | `.env.example` documents multi-provider usage with examples (opencode/litellm/llama_cpp) | Read .env.example |
| AC46 | All uncommitted changes committed to feature branch | `git status` clean after commit |
| AC47 | `bash generate.sh --dry-run` passes ALL validations with real .env | Run dry-run, check exit code 0 |
| AC48 | Generated configs produce callable LLM settings (model actually routes) | `opencode run` smoke test with generated config |
| AC49 | Generated Hermes overlay routes correctly with `hermes` CLI | Config validation |

## 12. CI/CD Pipeline (Phase 4 — in progress)

### 12.1 Files Added

| File | Purpose | Source |
|------|---------|--------|
| `.github/workflows/e2e.yml` | GitHub Actions CI: install bats + pyyaml, run generate.sh --dry-run, bats tests/e2e/*.bats | PORTED from Docker ref (host-adapted: no Docker, no compose, no healthcheck) |
| `tests/run.sh` | Test orchestrator: discovers all tests/e2e/*.bats, runs via bats, reports PASS/FAIL | PORTED from Docker ref |
| `tests/mock-llm-server.sh` | Lightweight mock LLM API server for offline testing | PORTED from Docker ref |

### 12.2 CI Design

- Runs on `ubuntu-latest`, no Docker dependency
- Installs `bats` from apt + `pyyaml` from pip
- Runs `generate.sh --dry-run` (sources .env.example as fixture)
- Runs `tests/run.sh` (full test suite)
- Expected runtime: ~2-3 minutes (no container build needed)
