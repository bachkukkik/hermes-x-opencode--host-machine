# Graph Report - hermes-x-opencode--host-machine  (2026-07-01)

## Corpus Check
- 19 files · ~14,809 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 190 nodes · 179 edges · 19 communities (13 shown, 6 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2e8c9478`
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

## God Nodes (most connected - your core abstractions)
1. `Standing Orders (ALWAYS apply)` - 9 edges
2. `PRD: Hermes × OpenCode Host Config Generator` - 9 edges
3. `Hermes × OpenCode Host Config Generator` - 9 edges
4. `01 — Architecture` - 9 edges
5. `02 — Config Generation` - 9 edges
6. `03 — Model Discovery` - 9 edges
7. `04 — Skill Installation` - 9 edges
8. `05 — Cross-Agent Delegation` - 9 edges
9. `06 — Verification` - 9 edges
10. `How` - 9 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Import Cycles
- None detected.

## Communities (19 total, 6 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.15
Nodes (12): 1. MANDATED SKILLS, 2. Kanban Delegation Rules (coding discipline), 3. Code Quality Rules, 4. Verification Commands, 5. File Locations (host paths), 6. LiteLLM / Model Discovery, 7. Project-Specific Patterns, 8. Agent Capabilities (+4 more)

### Community 1 - "Community 1"
Cohesion: 0.12
Nodes (16): 1. Summary, 2. Contacts, 3. Background, 4. Objective, 5. Market Segment, 6. Value Proposition, 7.1 Architecture, 7.2 Key Features (+8 more)

### Community 2 - "Community 2"
Cohesion: 0.20
Nodes (9): Applying the staging output (manual step), Edge cases handled, Environment variables, File layout, Hermes × OpenCode Host Config Generator, Origin / Related, Strict requirement: free Zen model, Usage (+1 more)

### Community 3 - "Community 3"
Cohesion: 0.53
Nodes (4): _fail(), _pass(), snapshot_live_checksums(), generate.sh script

### Community 4 - "Community 4"
Cohesion: 0.13
Nodes (7): common.bash script, seed_all_configs(), seed_env_file(), seed_hermes_config(), seed_opencode_config(), stop_mock_llm(), teardown()

### Community 5 - "Community 5"
Cohesion: 0.40
Nodes (4): Multi-PR Decomposition, PR Breakdown — Host Config Generator Gap Bridge, Provisioning Strategy, Verification Chain

### Community 12 - "Community 12"
Cohesion: 0.11
Nodes (17): 06 — Verification, Applying staging to live (manual step), bash -n syntax check, bats e2e tests, Checksum snapshot, Content assertions, --dry-run mode, How (+9 more)

### Community 13 - "Community 13"
Cohesion: 0.12
Nodes (16): 02 — Config Generation, config-hermes.sh overlay, config-opencode.sh MERGE strategy, constants.sh paths, env-auth.sh credential staging, Environment-gated config blocks, Environment variable reference, Fallback chain (+8 more)

### Community 14 - "Community 14"
Cohesion: 0.12
Nodes (15): 05 — Cross-Agent Delegation, Credential flow, Delegation matrix, Fallback chain, Hermes → OpenCode delegation, How, Model selection for delegation, OpenCode → Hermes delegation (+7 more)

### Community 15 - "Community 15"
Cohesion: 0.13
Nodes (14): 03 — Model Discovery, Authentication (EC2), Discovery pipeline, Fallback logic (EC1), Filter pipeline, How, Output format, Resolution (+6 more)

### Community 16 - "Community 16"
Cohesion: 0.13
Nodes (14): 04 — Skill Installation, Cross-agent skill sharing matrix, Host vs. Docker container differences, How, install-skills.sh pattern, Resolution, Skill directory layout, Skill YAML frontmatter (+6 more)

### Community 17 - "Community 17"
Cohesion: 0.14
Nodes (13): 01 — Architecture, Data flow, File layout, How, MERGE mode vs. Docker OVERWRITE, Resolution, Staging pipeline, Verdict (+5 more)

### Community 18 - "Community 18"
Cohesion: 0.40
Nodes (4): Architecture Documentation, Document Conventions, Document Index, Related Documents

## Knowledge Gaps
- **120 isolated node(s):** `config-hermes.sh script`, `config-opencode.sh script`, `constants.sh script`, `HERMES_HOME`, `env-auth.sh script` (+115 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `config-hermes.sh script`, `config-opencode.sh script`, `constants.sh script` to the rest of the system?**
  _120 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Should `Community 4` be split into smaller, more focused modules?**
  _Cohesion score 0.1286549707602339 - nodes in this community are weakly interconnected._
- **Should `Community 12` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._
- **Should `Community 13` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Should `Community 14` be split into smaller, more focused modules?**
  _Cohesion score 0.125 - nodes in this community are weakly interconnected._
- **Should `Community 15` be split into smaller, more focused modules?**
  _Cohesion score 0.13333333333333333 - nodes in this community are weakly interconnected._