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
| G-01 | All model fields (default, small, agent, fallback) should carry explicit provider prefixes | Host wrote raw `OPENCODE_DEFAULT_MODEL` directly — bare ids had no explicit routing | Bare model ids (no `opencode/`, `litellm/`, or `llama_cpp/` prefix) were written as-is, leaving provider routing implicit and inconsistent with the fallback chain (which did partial resolution). Fixed by `normalize_model()`: explicit prefixes pass through unchanged; bare ids get a credentialed prefix (`litellm/` if OPENAI creds present, else `opencode/`). | Medium (resolved) |
| G-02 | Upstream resolves provider prefix PER model (default, small, fallback) independently | Host resolves fallback per-entry but treats default model as-is | When `OPENCODE_DEFAULT_MODEL=opencode/deepseek-v4-flash-free`, host writes this directly — correct. When `llama_cpp/...`, host also writes directly — correct. **No gap** for top-level model fields. | None |
| G-03 | Upstream `generate_opencode_config` writes direct config (OVERWRITE mode) | Host `generate_opencode_staging` MERGE mode | Architectural difference by design (staging-only safety). No gap to bridge. | None |
| G-04 | Upstream `.env.example` documents multi-provider fallback chains with examples | Host `.env.example` shows only single-model fallback | User cannot discover the multi-model fallback feature | Medium |
| G-05 | (merged into G-01 — same root cause) | Resolved by `normalize_model()` | Gap closed by `normalize_model()` — a single function (not the two-function `_strip`/`_resolve` approach from the Docker reference). The host extension recognizes `llama_cpp/` as a third explicit prefix because the host creates a `provider.llama_cpp` block. See `.hermes/plans/provider-prefix-resolution.md`. | Resolved |
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
| AC45 | Bare model id (no provider prefix) + OPENAI creds present resolves to `litellm/` prefix | Set `OPENCODE_DEFAULT_MODEL=deepseek-v4-flash-free` with mock creds, check staging model field |
| AC46 | Bare model id + no OPENAI creds resolves to `opencode/` (Zen fallback) | Same bare id with creds unset, check staging model field |
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

## 13. Agent Model Override — .env-Driven Independent Routing

### 13.1 Problem

The current generator ties `agent.build.model` and `agent.plan.model` to
`OPENCODE_DEFAULT_MODEL`. This means agent sub-block models cannot be
independently configured — the user cannot route agent delegation tasks to a
different provider than the top-level `model`. When
`OPENCODE_DEFAULT_MODEL=llama_cpp/qwen3.6-27b-q4_k_m` (local), all agent
sub-model routing also uses the local model, which may not be desirable for
agent operations that benefit from a faster cloud model.

### 13.2 Requirements

| ID | Requirement | Source |
|----|-------------|--------|
| AM-1 | New env var `OPENCODE_AGENT_MODEL` controls `agent.build.model` and `agent.plan.model` independently | User request |
| AM-2 | When `OPENCODE_AGENT_MODEL` is set, both agent sub-model fields use its value | User request |
| AM-3 | When `OPENCODE_AGENT_MODEL` is unset, agent sub-models fall back to `OPENCODE_DEFAULT_MODEL` (current behavior preserved) | Backward compat |
| AM-4 | `OPENCODE_AGENT_MODEL` supports any provider prefix (opencode/litellm/llama_cpp/bare) — same resolution rules as other OPENCODE_*_MODEL vars | MR-1 through MR-6 |
| AM-5 | `.env.example` documents `OPENCODE_AGENT_MODEL` with usage guidance | AM-5 |
| AM-6 | Merge summary output reflects the agent model source (env var or default) | EC5 |

### 13.3 Acceptance Criteria

| AC# | Criteria | Verification |
|-----|----------|--------------|
| AC50 | `OPENCODE_AGENT_MODEL=litellm/deepseek/deepseek-v4-flash` → staging opencode.jsonc has `agent.build.model` and `agent.plan.model` set to `litellm/deepseek/deepseek-v4-flash` | `grep '"model"' staging/opencode.jsonc` in agent sub-blocks |
| AC51 | `OPENCODE_AGENT_MODEL` unset → agent sub-models fall back to `OPENCODE_DEFAULT_MODEL` (backward compat) | Same grep, verify matches OPENCODE_DEFAULT_MODEL |
| AC52 | `OPENCODE_AGENT_MODEL=llama_cpp/qwen3.6-27b` → routes through llama_cpp provider in generated config | Check provider block presence |
| AC53 | `.env.example` contains `OPENCODE_AGENT_MODEL` with comment and example value | `grep OPENCODE_AGENT_MODEL .env.example` |
| AC54 | `bash generate.sh --dry-run` passes all validations with new env var | Exit code 0, all checks green |
| AC55 | Merge summary in staging shows agent model source clearly | `grep "agent" staging/opencode-merge-summary.txt` |
| AC56 | Summary preserved blocks lists only `permission, plugin` (user preference) | `grep "Preserved blocks" staging/opencode-merge-summary.txt` |

### 13.4 Implementation Scope

Files to modify:
- `lib/config-opencode.sh` — read `OPENCODE_AGENT_MODEL` from environment, apply to agent sub-blocks; update preserved-blocks summary
- `.env.example` — add `OPENCODE_AGENT_MODEL` documentation
- `lib/constants.sh` — add default constant (optional, env-driven is sufficient)

### 13.5 Assumptions

- `OPENCODE_AGENT_MODEL` env var naming follows the existing `OPENCODE_*_MODEL` convention
- Agent sub-models (build, plan) share the same override — no need for per-sub-block granularity
- No new bats tests are required for this phase (covered by existing dry-run verification + manual grep checks)
- The preserved blocks summary preference (permission, plugin only) is cosmetic — "server" and "experimental" blocks remain fully functional in generated config

## 14. Shell Env Export Bridge (Phase 1.6 — delegation runtime gap)

### Problem

`opencode.jsonc` uses `{env:OPENAI_API_KEY}` references that resolve from the
interactive shell environment at runtime. The generator's export bridge
(commit ce9083e) exports `OPENCODE_*/HERMES_*` vars but OMITS
`OPENAI_API_KEY` and `OPENAI_BASE_URL`. Result: `opencode run` fails with
"Authentication Error, No api key passed in" in any shell that hasn't
manually sourced `~/.hermes/.env`.

### Root cause

Two gaps:
1. Export bridge omission: `generate.sh` lines 60-63 don't include the two
   OpenAI vars that opencode's `{env:...}` resolution depends on.
2. No sourceable artifact: even with the bridge fixed, the generator runs in
   a subshell — its exports don't persist to the user's interactive shell.

### Solution

1. Add `OPENAI_API_KEY OPENAI_BASE_URL` to the export bridge in `generate.sh`.
2. Generate `staging/export-env.sh` — a sourceable script that exports all
   managed env vars. `--apply` deploys it to `~/.hermes/host-config-gen/`.
3. Document: `source ~/.hermes/host-config-gen/export-env.sh` before
   `opencode run`.

### Acceptance criteria

- AC-EXP1: `generate.sh --dry-run` writes `staging/export-env.sh` containing
  `export OPENAI_API_KEY=` and `export OPENAI_BASE_URL=`
- AC-EXP2: `generate.sh --apply` copies `export-env.sh` to the deployed
  directory
- AC-EXP3: Export bridge in `generate.sh` includes `OPENAI_API_KEY` and
  `OPENAI_BASE_URL`
- AC-EXP4: After sourcing export-env.sh, `opencode run "test"` succeeds
  without auth errors
- AC-EXP5: New bats test `08-export-env.bats` passes
- AC-EXP6: Existing tests 01-07 still pass

### Out of scope

- Modifying `~/.bashrc` (too invasive; user sources the helper manually)
- Managing `~/.config/opencode/settings.json` (manual workaround, not a
  generator-managed file per AGENTS.md)

## 15. Cross-Repo Gap Bridge (Docker reference audit)

### 15.1 Problem

The host config generator was modeled after the Docker stack's config-generation
pipeline. A systematic audit (2026-07-04, Docker HEAD `8f9f52a`, host HEAD
`8125b8c`) identified gaps where the Docker reference has features not yet
ported to the host generator.

### 15.2 Gap Matrix

| Gap ID | Severity | Docker Feature (PR) | Host Status | Action |
|--------|----------|-------------------|-------------|--------|
| GA-01 | HIGH | Plugin array generation in config-opencode.sh | PORTED — 24-plugin-generation.bats covers 2 test cases | PORTED ✓ |
| GA-02 | LOW | `_resolve_provider_prefix()` / `_strip_provider_prefix()` | Simpler direct-write approach, functionally equivalent | SKIP — Karpathy simplicity |
| GA-03 | MEDIUM | `validate_opencode_zen_key()` | PORTED (`lib/validate-zen.sh`, sourced by generate.sh) | CROSS-REF docs — code exists, doc coverage TBD |
| GA-04 | SKIP | `service-dashboard.sh` + dashboard service | Docker service lifecycle | SKIP |
| GA-05 | SKIP | `profile-righthand-man.sh` | Docker profile seeding | SKIP |
| GA-06 | SKIP | `seed-volumes.sh` | Docker volume seeding | SKIP |
| GA-07 | LOW | `symlink-cleanup.sh` | PORTED | PORTED ✓ |

### 15.3 Port Details: Plugin Array Generation (GA-01)

**Scope:** Add plugin array generation to `lib/config-opencode.sh` so fresh
installs (no existing opencode.jsonc) receive the default plugins:
- `@tarquinen/opencode-dcp@latest`
- `@franlol/opencode-md-table-formatter@latest`
- `cc-safety-net`
- `opencode-runtime-fallback` (only when `OPENCODE_FALLBACK_MODEL` is set)

**Success criteria:**
- `generate.sh --dry-run` with empty live config produces `staging/opencode.jsonc` containing `"plugin": [...]`
- Fallback plugin present only when `OPENCODE_FALLBACK_MODEL` is set
- Existing plugins in live config are preserved (MERGE behavior unchanged)
- All bats tests pass

### 15.4 Security Fix: export-env.sh permissions

**Scope:** Change `chmod +x` to `chmod 600` for `staging/export-env.sh`
to restrict access to files containing literal API keys.

**Success criteria:**
- `stat -c '%a' staging/export-env.sh` returns `600`
- File remains sourceable by owner's shell

### 15.5 Assumptions

- Plugin list matches the Docker reference's current set (3 base + 1 conditional)
- Plugin names are stable — if Docker updates plugin names, host should follow
- `chmod 600` is sufficient (owner read/write only; no execute needed for sourcing)

## 16. Opt-In Shell Integration (Phase 1.7 — `--shell-integration` flag)

### 16.1 Problem

The shell env export bridge (§14) generates and deploys `export-env.sh`, but the
file is only effective if the user manually sources it before every `opencode`
invocation. In practice users open a fresh shell, run `opencode .`, and hit
`Authentication Error, No api key passed in` — the Layer 3 failure documented in
`references/host-opencode-run-debugging.md`. The staging-only guarantee (§14
out-of-scope: "Modifying ~/.bashrc — too invasive") leaves no durable path.

### 16.2 Solution

Add an **opt-in** `--shell-integration` flag to `generate.sh`, valid only with
`--apply`. When set, after deploying `export-env.sh`, the generator appends a
single **guarded, idempotent, removable** source line to the user's shell rc
file (`~/.bashrc` for bash, `~/.zshrc` for zsh). The line is wrapped in sentinel
markers so re-runs do not duplicate it and a future `--remove-shell-integration`
can delete the block cleanly.

### 16.3 Behavior

- `generate.sh --apply` — unchanged; deploys config + export-env.sh, does NOT
  touch shell rc.
- `generate.sh --apply --shell-integration` — after apply, appends the guarded
  block to the detected rc file. Prints the exact file path and line added.
- `generate.sh --apply --shell-integration` re-run — detects existing block via
  sentinel markers, skips (no duplicate).
- `generate.sh --apply --remove-shell-integration` — removes the guarded block
  if present, exits 0 if absent (idempotent).
- `--shell-integration` without `--apply` — error and exit 1 (shell integration
  is meaningless without deploying export-env.sh first).
- Rc file selection: `$SHELL`-aware — bash → `~/.bashrc`, zsh → `~/.zshrc`,
  other → error with explicit "unsupported shell" message.

### 16.4 Guarded block format

```
# >>> hermes host-config-gen env bridge (managed, do not edit) >>>
[ -f "$HOME/.hermes/host-config-gen/export-env.sh" ] && source "$HOME/.hermes/host-config-gen/export-env.sh"
# <<< hermes host-config-gen env bridge <<<
```

### 16.5 Acceptance criteria

- AC-SI1: `generate.sh --apply --shell-integration` exits 0 and appends exactly
  one guarded block to the user's rc file
- AC-SI2: Re-running `generate.sh --apply --shell-integration` does NOT produce
  a duplicate block (idempotent)
- AC-SI3: `generate.sh --apply --remove-shell-integration` removes the block
  cleanly; re-run exits 0 (block absent = no-op)
- AC-SI4: `--shell-integration` without `--apply` exits non-zero with a clear
  error message
- AC-SI5: After integration, a fresh interactive shell (or `bash -i -c`) has
  `OPENAI_API_KEY` exported (len > 0)
- AC-SI6: Dry-run mode (`--apply --dry-run --shell-integration`) reports what
  would be added without modifying the rc file
- AC-SI7: New bats test `09-shell-integration.bats` covers AC-SI1 through
  AC-SI4 using a temp HOME
- AC-SI8: All existing tests (01-08) still pass
- AC-SI9: README updated with `--shell-integration` usage and the
  `--remove-shell-integration` rollback path
- AC-SI10: `bash -n generate.sh` passes after every change

### 16.6 Out of scope

- Editing rc files silently (the flag is explicit and opt-in)
- Supporting fish, nushell, or non-POSIX shells (bash/zsh only for now)
- Integrating with `~/.profile` or `~/.bash_profile` (bash interactive shells
  source `~/.bashrc`; non-interactive shells are out of scope)
- Migrating the double-prefix default model (`litellm/opencode/...`) — tracked
  separately; not an auth blocker

### 16.7 Security

- The rc file edit adds only a guarded `source` line referencing the deployed
  `export-env.sh` — no secrets inlined in the rc file
- `export-env.sh` remains `chmod 600` (§15.4)
- The sentinel markers make the change auditable: `grep -n 'hermes host-config-gen' ~/.bashrc`

## 17. Installation & Deployment Documentation (Phase 2 — docs parity)

### 17.1 Problem

The two-tier deployment model (repo → `~/.hermes/host-config-gen/`) is a core
architectural decision, but no dedicated document explains it. The pieces are
scattered across docs/02 (the .env portability subsection), docs/01 (the
deployed file layout tree), and README (usage examples that assume the
installed path). A user following the docs cannot answer: "What does
install.sh actually do?", "When must I redeploy?", or "Why did my lib/ edit
not take effect?" — the last being the **stale-deployed-copy pitfall** that
produces silently-wrong output (no error, just old behavior).

### 17.2 Solution

Create a dedicated `docs/07-installation-deployment.md` following the existing
8-section coding-agents-docs-guideline template (What / Why / How / Verification
/ What Works / What Fails / Resolution / Verdict). Add it to the docs/README.md
index. Do NOT duplicate docs/02's .env portability section — cross-reference it.

### 17.3 Content scope

The new doc must cover:

1. **Two-tier model** — repo (git-tracked, source of truth) vs. deployed copy
   (`~/.hermes/host-config-gen/`, flat `cp` by install.sh). Diagram showing the
   relationship.
2. **install.sh operation** — what files it copies (generate.sh, README.md,
   lib/*.sh, .env), the `DEST` constant, prerequisite checks, `--no-run` flag,
   and the post-install dry-run validation.
3. **The `--no-run` flag** — install without running the generator; the standard
   pre-verification recipe: `install.sh --no-run && generate.sh --dry-run`.
4. **sync-env.sh** — the managed-section .env sync (brief; cross-ref docs/02 for
   the full managed-marker mechanics).
5. **Stale-deployed-copy pitfall** (What Fails section) — when only lib/ files
   change (not generate.sh), a naive diff passes but the deployed lib/ is stale.
   Symptom: no error, new feature simply absent from output. Fix: always
   redeploy via `install.sh --no-run` before verification.
6. **In-repo vs. installed-path workflows** — both are valid; in-repo for
   development, installed-path for production. Cross-ref the README "In-repo
   usage" subsection.
7. **Verification commands** — `diff generate.sh ~/.hermes/host-config-gen/generate.sh`,
   `install.sh --no-run` recipe, confirming deployed copy matches repo after edit.

### 17.4 Acceptance criteria

- AC-DOC1: `docs/07-installation-deployment.md` exists and follows the 8-section
  template (What/Why/How/Verification/What Works/What Fails/Resolution/Verdict)
- AC-DOC2: The stale-deployed-copy pitfall is documented with its symptom
  ("silently-wrong output, no error") and fix (`install.sh --no-run` recipe)
- AC-DOC3: The two-tier model is shown as a diagram (ASCII or mermaid) with the
  repo→deployed copy→live paths relationship
- AC-DOC4: `docs/README.md` index table is updated with row 07
- AC-DOC5: The doc cross-references docs/02 (for .env portability) and docs/01
  (for file layout) rather than duplicating their content
- AC-DOC6: install.sh's `--no-run` flag and the `install.sh --no-run &&
  generate.sh --dry-run` verification recipe are documented
- AC-DOC7: No other files are modified (no PRD/generate.sh/test changes)
- AC-DOC8: Markdown is well-formed (code fences balanced, tables valid)

### 17.5 Out of scope

- Rewriting docs/02's .env portability section (cross-ref only)
- Rewriting docs/01's file layout (cross-ref only)
- Adding a `--force` or `--diff` flag to install.sh (documentation only, no
  code changes to install.sh in this phase)
- Docker-stack installation (docs are host-only; Docker is the reference, not
  the subject)

## 18. In-Repo Execution Fix (Phase 2.1)

### 18.1 Problem

Running `bash generate.sh` directly from the repo root on a fresh machine (no
`install.sh` yet) fails with:

```
generate.sh: line 93: /root/.hermes/host-config-gen/lib/model-discovery.sh: No such file or directory
```

**Root cause:** `generate.sh` sets `LIB_DIR="${SCRIPT_DIR}/lib"` (repo path) on
line 29, then sources `constants.sh` on line 69. `constants.sh` line 20
unconditionally overwrites `LIB_DIR` to `${GEN_DIR}/lib` (`~/.hermes/host-config-gen/lib`),
the installed path. All subsequent `source` calls resolve from the installed path,
which doesn't exist until `install.sh` is run.

### 18.2 Fix

**File:** `lib/constants.sh`, line 20

**Change:** Unconditional assignment → parameter expansion with default:

```diff
-LIB_DIR="${GEN_DIR}/lib"
+LIB_DIR="${LIB_DIR:-${GEN_DIR}/lib}"
```

The `:-` expansion preserves a pre-set `LIB_DIR` (set by `generate.sh` before
sourcing) and falls back to `${GEN_DIR}/lib` only when unset. This handles all
three execution contexts:

| Context | generate.sh pre-sets LIB_DIR | constants.sh behavior |
|---------|------------------------------|----------------------|
| In-repo (`bash generate.sh`) | `<repo>/lib/` | Preserves `<repo>/lib/` |
| Installed (`bash ~/.hermes/.../generate.sh`) | `~/.hermes/host-config-gen/lib/` | Preserves installed path |
| `constants.sh` sourced standalone | unset | Defaults to installed path |

### 18.3 Verification

Both paths pass all 19 validation checks:

- `install.sh --no-run && bash ~/.hermes/host-config-gen/generate.sh --dry-run` — 19/19 passed
- `bash generate.sh --dry-run` (in-repo, no install.sh) — 19/19 passed

### 18.4 Success criteria

- SC-FIX1: `bash generate.sh --dry-run` from repo root on fresh machine succeeds
- SC-FIX2: Installed-path workflow unchanged (regression-free)
- SC-FIX3: `bash -n lib/constants.sh` passes
- SC-FIX4: All bats tests pass with the change
- SC-FIX5: Staging output identical between in-repo and installed-path runs

## 19. DEFAULT_CONTEXT_LENGTHS + Agents A1 Pin Table (Phase 2.2)

### 19.1 Problem

The host config generators (`config-hermes.sh` `resolve_ctx_len()` and
`config-opencode.sh` `get_limits()`) have no entries for the
`llama_cpp/agents-a1-mtp-apex-i-balanced` model (native 262,144 context per
GGUF metadata). The `resolve_ctx_len()` returns empty (agent self-resolves),
and the agent's own `DEFAULT_CONTEXT_LENGTHS` table substring-matches
`"llama" → 131,072` inside `"llama_cpp/agents-a1-..."` — wrong value.

Separately, the default-model fallback context length is hardcoded `200000`
in `config-hermes.sh`. There is no env-var mechanism to configure it.

### 19.2 Root cause

| Layer | Why | Current | Fix |
|-------|-----|---------|-----|
| Agent runtime `DEFAULT_CONTEXT_LENGTHS` | `"llama": 131072` matches inside `llama_cpp/...` (prefix not stripped) | 131,072 | Per-model `context_length` in config.yaml (done in prior session) |
| Host `config-hermes.sh` `resolve_ctx_len()` | No agents-a1 entries | Empty → self-resolve | Pin table entries: 262,144 |
| Host `config-opencode.sh` `get_limits()` | Falls to generic `llama_cpp → 200000` | 200,000 (wrong) | Specific entries: 262,144 |
| Hardcoded 200000 default-model fallback | Not configurable via env | 200,000 | `DEFAULT_CONTEXT_LENGTHS` env var |

### 19.3 Fix

**Files changed:**

- **`.env.example`**: Added `DEFAULT_CONTEXT_LENGTHS=200000` env var with documentation
- **`lib/constants.sh`**: Export `DEFAULT_CONTEXT_LENGTHS="${DEFAULT_CONTEXT_LENGTHS:-200000}"`
- **`lib/config-hermes.sh`** `resolve_ctx_len()` (bash + Python): Added `*agents-a1-mtp-apex*` → 262,144 and `*agents-a1-q4*` → 262,144 entries. Replaced hardcoded `200000` on line 152 with `int(os.environ.get("DEFAULT_CONTEXT_LENGTHS", "200000"))`.
- **`lib/config-opencode.sh`** `get_limits()`: Added `agents-a1-mtp-apex` → 262,144, 32,768 and `agents-a1-q4` → 262,144, 32,768 before the `qwen3.6-27b` check in the `llama_cpp` branch.
- **`docs/02-config-generation.md`**: Updated `resolve_ctx_len` table + `DEFAULT_CONTEXT_LENGTHS` documentation
- **`tests/e2e/03-config-validity.bats`**: Added `resolve_ctx_len` tests for agents-a1 models

### 19.4 Design principle (karpathy §6 — Single Source of Truth)

The `DEFAULT_CONTEXT_LENGTHS` env var becomes the single configurable fallback.
Previously the value `200000` appeared as a hardcoded integer in the Python
heredoc inside `config-hermes.sh`. Adding an entry that needed a different
default would have required editing the script. Now it reads from the env.

The agents-a1 pin table entries use the longest-match-first ordering principle
already established by `qwen3.6-27b+q4` (specific quantized variant before
family wildcard). `*agents-a1-mtp-apex*` is checked before any broader
`llama` or generic catch-all.

### 19.5 Success criteria

- SC-DCL1: `grep -c 'DEFAULT_CONTEXT_LENGTHS' .env.example` → ≥ 1
- SC-DCL2: `grep -c 'DEFAULT_CONTEXT_LENGTHS' lib/constants.sh` → ≥ 1
- SC-DCL3: `resolve_ctx_len "llama_cpp/agents-a1-mtp-apex-i-balanced"` → `262144`
- SC-DCL4: `resolve_ctx_len "llama_cpp/agents-a1-q4_k_m"` → `262144`
- SC-DCL5: `get_limits("llama_cpp/agents-a1-mtp-apex-i-balanced")` → `(262144, 32768)`
- SC-DCL6: `bash -n` passes on all shell files
- SC-DCL7: `bash generate.sh --dry-run` passes all internal validation checks
- SC-DCL8: `bats tests/e2e/03-config-validity.bats` — all resolve_ctx_len tests pass
- SC-DCL9: Staging `config-hermes-overlay.yaml` contains `context_length: 262144` for agents-a1 models
- SC-DCL10: Default model fallback uses `DEFAULT_CONTEXT_LENGTHS` value, not hardcoded 200000
