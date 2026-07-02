# Graph Report - hermes-x-opencode--host-machine  (2026-07-02)

## Corpus Check
- 20 files · ~16,999 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 223 nodes · 219 edges · 21 communities (15 shown, 6 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `07fd08a1`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

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

## God Nodes (most connected - your core abstractions)
1. `PRD: Hermes × OpenCode Host Config Generator` - 12 edges
2. `06 — Verification` - 11 edges
3. `Standing Orders (ALWAYS apply)` - 9 edges
4. `Hermes × OpenCode Host Config Generator` - 9 edges
5. `01 — Architecture` - 9 edges
6. `02 — Config Generation` - 9 edges
7. `03 — Model Discovery` - 9 edges
8. `04 — Skill Installation` - 9 edges
9. `05 — Cross-Agent Delegation` - 9 edges
10. `How` - 9 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Import Cycles
- None detected.

## Communities (21 total, 6 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.15
Nodes (12): 1. MANDATED SKILLS, 2. Kanban Delegation Rules (coding discipline), 3. Code Quality Rules, 4. Verification Commands, 5. File Locations (host paths), 6. LiteLLM / Model Discovery, 7. Project-Specific Patterns, 8. Agent Capabilities (+4 more)

### Community 1 - "Community 1"
Cohesion: 0.09
Nodes (23): 10.1 Missing Docs (Phase 2 items), 10.2 Missing Tests (Phase 2 items), 10.3 Knowledge Layer (Phase 3 items), 10. Documentation and Testing Gaps, 11. CI/CD Pipeline (Phase 4), 1. Summary, 2. Contacts, 3. Background (+15 more)

### Community 2 - "Community 2"
Cohesion: 0.20
Nodes (9): Applying the staging output (manual step), Edge cases handled, Environment variables, File layout, Hermes × OpenCode Host Config Generator, Origin / Related, Strict requirement: free Zen model, Usage (+1 more)

### Community 3 - "Community 3"
Cohesion: 0.53
Nodes (4): _fail(), _pass(), generate.sh script, snapshot_live_checksums()

### Community 4 - "Community 4"
Cohesion: 0.13
Nodes (7): common.bash script, seed_all_configs(), seed_env_file(), seed_hermes_config(), seed_opencode_config(), stop_mock_llm(), teardown()

### Community 5 - "Community 5"
Cohesion: 0.40
Nodes (4): Multi-PR Decomposition, PR Breakdown — Host Config Generator Gap Bridge, Provisioning Strategy, Verification Chain

### Community 12 - "Community 12"
Cohesion: 0.11
Nodes (19): 06 — Verification, Applying staging to live (manual step), bash -n syntax check, bats e2e tests, Checksum snapshot, Content assertions, Credential Resolution (PR #66 / CA-30-A), --dry-run mode (+11 more)

### Community 13 - "Community 13"
Cohesion: 0.12
Nodes (16): 02 — Config Generation, config-hermes.sh overlay, config-opencode.sh MERGE strategy, constants.sh paths, env-auth.sh credential staging, Environment-gated config blocks, Environment variable reference, Fallback chain (+8 more)

### Community 14 - "Community 14"
Cohesion: 0.12
Nodes (15): 05 — Cross-Agent Delegation, Credential flow, Delegation matrix, Fallback chain, Hermes → OpenCode delegation, How, Model selection for delegation, OpenCode → Hermes delegation (+7 more)

### Community 15 - "Community 15"
Cohesion: 0.12
Nodes (15): 03 — Model Discovery, Authentication (EC2), Discovery pipeline, Fallback logic (EC1), Filter pipeline, How, Output format, Quantized GGUF context-length pin (PR #66 / CA-31-A) (+7 more)

### Community 16 - "Community 16"
Cohesion: 0.14
Nodes (14): 04 — Skill Installation, Cross-agent skill sharing matrix, Host vs. Docker container differences, How, install-skills.sh pattern, Resolution, Skill directory layout, Skill YAML frontmatter (+6 more)

### Community 17 - "Community 17"
Cohesion: 0.14
Nodes (13): 01 — Architecture, Data flow, File layout, How, MERGE mode vs. Docker OVERWRITE, Resolution, Staging pipeline, Verdict (+5 more)

### Community 18 - "Community 18"
Cohesion: 0.22
Nodes (4): Architecture Documentation, Document Conventions, Document Index, Related Documents

### Community 19 - "Community 19"
Cohesion: 0.12
Nodes (16): Assumptions, Changes Summary, Cross-Repo Bridge Gap Implementation Plan, Docs (content updates), Feature 1: OPENCODE_ZEN_API_KEY → OPENCODE_ZEN_API_KEY rename (PR #68), Feature 2: Per-delegation model routing (PR #68), Feature 3: auth.json OR guard contract (PR #66), HARD Gate: PLAN-1 Output (+8 more)

### Community 20 - "Community 20"
Cohesion: 0.33
Nodes (6): 7.1 Architecture, 7.2 Key Features, 7.3 Model Selection Defaults, 7.4 Cross-Agent Delegation, 7.5 Assumptions, 7. Solution

## Knowledge Gaps
- **145 isolated node(s):** `config-hermes.sh script`, `config-opencode.sh script`, `constants.sh script`, `HERMES_HOME`, `env-auth.sh script` (+140 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PRD: Hermes × OpenCode Host Config Generator` connect `Community 1` to `Community 18`, `Community 20`?**
  _High betweenness centrality (0.143) - this node is a cross-community bridge._
- **Why does `06 — Verification` connect `Community 12` to `Community 18`?**
  _High betweenness centrality (0.096) - this node is a cross-community bridge._
- **Why does `02 — Config Generation` connect `Community 13` to `Community 18`?**
  _High betweenness centrality (0.081) - this node is a cross-community bridge._
- **What connects `config-hermes.sh script`, `config-opencode.sh script`, `constants.sh script` to the rest of the system?**
  _145 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.08695652173913043 - nodes in this community are weakly interconnected._
- **Should `Community 4` be split into smaller, more focused modules?**
  _Cohesion score 0.1286549707602339 - nodes in this community are weakly interconnected._
- **Should `Community 12` be split into smaller, more focused modules?**
  _Cohesion score 0.10526315789473684 - nodes in this community are weakly interconnected._