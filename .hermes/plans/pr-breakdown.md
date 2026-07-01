# PR Breakdown — Host Config Generator Gap Bridge

## Multi-PR Decomposition

Single PR covering all gaps (same subsystem — host config generator).

| # | Concern | Files | Dependency |
|---|---------|-------|------------|
| 1 | AGENTS.md + PRD.md | AGENTS.md (new), PRD.md (new) | None |
| 2 | config-hermes ctx_len fix | lib/config-hermes.sh (patch) | None |
| 3 | config-opencode fallback chain | lib/config-opencode.sh (patch) | None |
| 4 | docs/ directory | docs/*.md (new) | None |
| 5 | tests/ directory | tests/*.bats (new) | None |
| 6 | graphify-out + llm-wiki | graphify-out/ + ~/wiki/ | None |

All concerns are independent — single branch, single PR.

## Provisioning Strategy

All are repo-tracked files within this project — no external dependencies to provision.

## Verification Chain

After all waves: `bash generate.sh --dry-run && bats tests/`
