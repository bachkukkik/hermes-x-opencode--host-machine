# Architecture Documentation

Comprehensive technical documentation for the Hermes × OpenCode Host Config Generator. Each document follows the 8-section template (What, Why, How, Verification, What Works, What Fails, Resolution, Verdict).

## Document Index

| # | Document | Subsystem |
|---|----------|-----------|
| 01 | [Architecture](01-architecture.md) | Staging pipeline, MERGE mode, file layout, data flow, Docker vs. host comparison |
| 02 | [Config Generation](02-config-generation.md) | constants.sh paths, config-opencode.sh MERGE strategy (provider.opencode + litellm + llama_cpp), config-hermes.sh overlay, env-auth.sh credential staging, env var reference table, fallback chain |
| 03 | [Model Discovery](03-model-discovery.md) | LiteLLM /v1/models endpoint, filter pipeline (15 regex patterns), case-insensitive dedup, EC1 fallback, in-process key safety (EC2) |
| 04 | [Skill Installation](04-skill-installation.md) | Host skill layout vs. Docker container, cross-agent skill sharing (Hermes → OpenCode), install-skills.sh pattern, YAML frontmatter, symlink lifecycle |
| 05 | [Cross-Agent Delegation](05-cross-agent-delegation.md) | Hermes→OpenCode via opencode skill (free Zen model), OpenCode→Hermes via hermes terminal tool (LiteLLM proxy), llama_cpp fallback routing, model selection matrix, credential flow |
| 06 | [Verification](06-verification.md) | Four-layer verification design, --dry-run checksum snapshot, bash -n / JSON / YAML validation, content assertions, bats e2e test plan, --apply flag for live deployment |

## Related Documents

- [README.md](../README.md) — Project overview, usage, and quick start
- [PRD.md](../PRD.md) — Product requirements, key results, and release phases

## Document Conventions

All documents in this directory follow the [coding-agents-docs-guideline](https://github.com/bachkukkik/hermes-x-opencode) 8-section template:

- **What** — One-sentence definition
- **Why** — Reasons it exists
- **How** — Technical details with tables, code blocks, and sub-headings
- **Verification** — Runnable shell commands to confirm functionality
- **What Works** — Confirmed working behaviors
- **What Fails** — Known issues with **bold** issue names
- **Resolution** — 1:1 mapping with What Fails
- **Verdict** — Overall fitness assessment

Writing style: present tense, active voice, third person, no filler.
