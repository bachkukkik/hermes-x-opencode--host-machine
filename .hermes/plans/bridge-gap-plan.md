# Cross-Repo Bridge Gap Implementation Plan

## HARD Gate: PLAN-1 Output

### Scope
Bridge implementation gaps between host config generator (this repo) and the reference Docker stack (hermes-x-opencode). Three features to port from reference PRs #66 and #68.

### Changes Summary

#### Feature 1: OPENCODE_ZEN_API_KEY → OPENCODE_ZEN_API_KEY rename (PR #68)
| File | Change |
|------|--------|
| `.env.example` | Rename `OPENCODE_ZEN_API_KEY` → `OPENCODE_ZEN_API_KEY`, update comment |
| `lib/config-opencode.sh` | `{env:OPENCODE_ZEN_API_KEY}` → `{env:OPENCODE_ZEN_API_KEY}` (line 155, 240) |
| `lib/env-auth.sh` | Read `OPENCODE_ZEN_API_KEY` instead of `OPENCODE_ZEN_API_KEY`, update summary text |
| `docs/02-config-generation.md` | Update all OPENCODE_ZEN_API_KEY references |
| All tests/ | Update assertions |

#### Feature 2: Per-delegation model routing (PR #68)
| File | Change |
|------|--------|
| `.env.example` | Add `HERMES_DELEGATION_MODEL` and `HERMES_DELEGATION_PROVIDER` (commented) |
| `lib/config-hermes.sh` | After `delegation.max_iterations`, conditionally write `delegation.model` and `delegation.provider` |

#### Feature 3: auth.json OR guard contract (PR #66)
| File | Change |
|------|--------|
| `lib/env-auth.sh` | Add contract comment documenting OR logic |

#### Tests (new files)
| File | Content |
|------|--------|
| `tests/e2e/20-zen-api-key.bats` | AC34: OPENCODE_ZEN_API_KEY in opencode.jsonc + auth.json |
| `tests/e2e/21-delegation-model.bats` | AC35: delegation.model/provider in staging overlay |
| `tests/e2e/22-ctx-pin-and-credentials.bats` | CTX1-3: quantized GGUF ctx pin, CRED1-2: auth.json OR guard |

#### Docs (content updates)
| File | Update |
|------|--------|
| `docs/02-config-generation.md` | OPENCODE_ZEN_API_KEY + delegation routing section |
| `docs/03-model-discovery.md` | Quantized GGUF ctx pin subsection |
| `docs/06-verification.md` | Credential resolution paragraph |

### Assumptions
- Assumption: Reference PR #68 is the authoritative source for OPENCODE_ZEN_API_KEY naming convention
- Assumption: Host tests use same helper (`tests/e2e/test_helper/common.bash`) pattern
- Assumption: `generate.sh --dry-run` is the primary verification command

### Success Criteria
1. `bash -n` passes on all modified .sh files
2. `generate.sh --dry-run` produces staging with `{env:OPENCODE_ZEN_API_KEY}`
3. `bats tests/e2e/` all pass
4. Zero `OPENCODE_ZEN_API_KEY` references remain (grep check)
5. Delegation model test passes with env var set

### PR Breakdown
Single PR: "feat: bridge gaps from reference PR #66 + #68"
- Branch: `feat/bridge-gap-pr66-68`

---

## Wave Decomposition

### Wave 1: Code changes (3 independent subagents)
1. OPENCODE_ZEN_API_KEY rename (config-opencode.sh + env-auth.sh + .env.example)
2. Per-delegation model routing (config-hermes.sh + .env.example)
3. auth.json OR guard contract comment (env-auth.sh)

⚠ Files overlap: .env.example touched by Wave 1 tasks 1+2, env-auth.sh touched by tasks 1+3.
→ Reconciliation required after Wave 1.

### Wave 2: Tests (3 independent subagents)
1. tests/e2e/20-zen-api-key.bats
2. tests/e2e/21-delegation-model.bats
3. tests/e2e/22-ctx-pin-and-credentials.bats

### Wave 3: Docs (3 independent subagents)
1. docs/02-config-generation.md
2. docs/03-model-discovery.md
3. docs/06-verification.md
