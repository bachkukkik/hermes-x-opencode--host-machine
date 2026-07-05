# Graph Report - .  (2026-07-05)

## Corpus Check
- 25 files · ~25,491 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 153 nodes · 147 edges · 27 communities (10 shown, 17 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]

## God Nodes (most connected - your core abstractions)
1. `Hermes × OpenCode Host Config Generator` - 9 edges
2. `generate.sh` - 9 edges
3. `lib/config-opencode.sh` - 9 edges
4. `HARD Gate: PLAN-1 Output` - 6 edges
5. `Changes Summary` - 6 edges
6. `Main Orchator Script` - 6 edges
7. `staging/` - 6 edges
8. `lib/model-discovery.sh` - 5 edges
9. `lib/config-hermes.sh` - 5 edges
10. `Wave Decomposition` - 4 edges

## Surprising Connections (you probably didn't know these)
- `generate.sh` --references--> `E2E CI Pipeline`  [EXTRACTED]
  PRD.md → .github/workflows/e2e.yml
- `generate.sh` --conceptually_related_to--> `Staging Pipeline Architecture`  [EXTRACTED]
  PRD.md → docs/01-architecture.md
- `generate.sh` --conceptually_related_to--> `Verification Checksum Snapshot`  [EXTRACTED]
  PRD.md → docs/06-verification.md
- `lib/model-discovery.sh` --conceptually_related_to--> `Model Discovery Filter Pipeline`  [EXTRACTED]
  PRD.md → docs/03-model-discovery.md
- `lib/config-opencode.sh` --conceptually_related_to--> `Config Generation MERGE Strategy`  [EXTRACTED]
  PRD.md → docs/02-config-generation.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Core Staging Pipeline Modules** — agents_generate_sh, lib_model_discovery_sh, lib_config_opencode_sh, lib_config_hermes_sh, lib_env_auth_sh [EXTRACTED 0.95]
- **Staging Pipeline Components** — prd_generate_sh, prd_lib_model_discovery_sh, prd_lib_config_opencode_sh, prd_lib_config_hermes_sh, prd_lib_env_auth_sh, prd_staging_dir [EXTRACTED 0.95]
- **Cross-Agent Delegation Flow** — prd_hermes_agent, prd_opencode_cli, prd_litellm_proxy, prd_opencode_zen_api_key, prd_openai_api_key [EXTRACTED 0.95]

## Communities (27 total, 17 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.13
Nodes (22): E2E CI Pipeline, Staging Pipeline Architecture, Config Generation MERGE Strategy, Verification Checksum Snapshot, auth.json, config-hermes-overlay.yaml, export-env.sh, generate.sh (+14 more)

### Community 1 - "Community 1"
Cohesion: 0.13
Nodes (7): common.bash script, seed_all_configs(), seed_env_file(), seed_hermes_config(), seed_opencode_config(), stop_mock_llm(), teardown()

### Community 2 - "Community 2"
Cohesion: 0.12
Nodes (16): Assumptions, Changes Summary, Cross-Repo Bridge Gap Implementation Plan, Docs (content updates), Feature 1: OPENCODE_ZEN_API_KEY → OPENCODE_ZEN_API_KEY rename (PR #68), Feature 2: Per-delegation model routing (PR #68), Feature 3: auth.json OR guard contract (PR #66), HARD Gate: PLAN-1 Output (+8 more)

### Community 3 - "Community 3"
Cohesion: 0.13
Nodes (13): Architecture Documentation, Document Conventions, Document Index, Related Documents, Applying configs, Edge cases handled, Environment variables, File layout (+5 more)

### Community 4 - "Community 4"
Cohesion: 0.17
Nodes (12): Main Orchator Script, Deployment Script, End-to-End Test Suite, Default Hermes Model, Hermes Config Overlay Generator, OpenCode Config Merge Generator, Credential Resolution Library, LiteLLM Model Discovery Library (+4 more)

### Community 5 - "Community 5"
Cohesion: 0.24
Nodes (11): Model Discovery Filter Pipeline, Cross-Agent Skill Sharing, Cross-Agent Delegation Flow, hermes-x-opencode Docker Stack, Hermes Agent, lib/model-discovery.sh, LiteLLM Proxy, OPENAI_BASE_URL (+3 more)

### Community 6 - "Community 6"
Cohesion: 0.53
Nodes (4): _fail(), _pass(), generate.sh script, snapshot_live_checksums()

### Community 7 - "Community 7"
Cohesion: 0.40
Nodes (4): Multi-PR Decomposition, PR Breakdown — Host Config Generator Gap Bridge, Provisioning Strategy, Verification Chain

### Community 8 - "Community 8"
Cohesion: 0.50
Nodes (4): Hermes and OpenCode Task Routing, Hermes AI Agent Platform, Reference Docker Stack Repository, OpenCode CLI Coding Agent

### Community 14 - "Community 14"
Cohesion: 0.67
Nodes (3): Host Paths and Defaults Library, Default OpenCode Model, OpenAI-Compatible Endpoint URL

## Knowledge Gaps
- **67 isolated node(s):** `Scope`, `Feature 1: OPENCODE_ZEN_API_KEY → OPENCODE_ZEN_API_KEY rename (PR #68)`, `Feature 2: Per-delegation model routing (PR #68)`, `Feature 3: auth.json OR guard contract (PR #66)`, `Tests (new files)` (+62 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.