# 04 — Skill Installation

## What

Skills are shareable Markdown instruction files that extend agent capabilities. On the host, Hermes and OpenCode load skills from different directories, but the host config generator enables cross-agent sharing via a unified skill-installation pattern.

## Why

- Hermes Agent and OpenCode CLI have distinct skill discovery paths. Hermes loads from `~/.hermes/skills/` while OpenCode loads from `~/.config/opencode/skills/`. Without coordination, skills installed for one agent are invisible to the other.
- The Docker reference stack pre-loads skills into container volumes. The host must replicate this with a shell-based install script that provisions skills to both agent paths.
- Cross-agent delegation (Hermes → OpenCode and OpenCode → Hermes) requires both agents to have access to the same skill definitions for consistent behavior.

## How

### Skill directory layout

```
~/.hermes/skills/                        # Hermes Agent skill root
├── software-development/
│   ├── coding-agents-docs-guideline/SKILL.md
│   ├── karpathy-guidelines/SKILL.md
│   └── ...
├── autonomous-ai-agents/
│   ├── opencode-plan-build-orchestrator/SKILL.md
│   ├── opencode/SKILL.md
│   └── hermes-agent/SKILL.md
├── devops/
│   ├── kanban-orchestrator/SKILL.md
│   └── hermes-opencode-host-install/SKILL.md
└── ...

~/.config/opencode/skills/               # OpenCode CLI skill root
├── opencode/SKILL.md
├── coding-agents-docs-guideline/SKILL.md
└── ...
```

Each skill is a directory containing a `SKILL.md` file with YAML frontmatter and instructions. Hermes discovers skills recursively; OpenCode typically expects flat or shallow-nested directories.

### install-skills.sh pattern

> [!NOTE]
> **PLANNED / NOT YET IMPLEMENTED:** The `install-skills.sh` script and the automated clone/symlink flow documented below are currently planned/aspirational. Only `install.sh` exists in the repository at this time.

The host-level install script follows the Docker reference pattern:

```bash
#!/usr/bin/env bash
# install-skills.sh — provision shared skills for Hermes + OpenCode
set -euo pipefail

HERMES_SKILLS="${HOME}/.hermes/skills"
OPENCODE_SKILLS="${HOME}/.config/opencode/skills"

# Clone or update skill repositories
clone_or_update() {
    local repo_url="$1"
    local dest="$2"
    if [ -d "$dest/.git" ]; then
        (cd "$dest" && git pull --ff-only)
    else
        git clone "$repo_url" "$dest"
    fi
}

# Example: install the opencode skill for both agents
clone_or_update "https://github.com/bachkukkik/hermes-opencode-skill" \
    "${HERMES_SKILLS}/autonomous-ai-agents/opencode"

# Symlink to OpenCode's skill directory for cross-agent visibility
mkdir -p "${OPENCODE_SKILLS}"
ln -sfn "${HERMES_SKILLS}/autonomous-ai-agents/opencode" \
    "${OPENCODE_SKILLS}/opencode"
```

### Cross-agent skill sharing matrix

| Skill | Hermes path | OpenCode path | Sharing method |
|-------|-------------|---------------|----------------|
| `opencode` | `~/.hermes/skills/autonomous-ai-agents/opencode/` | `~/.config/opencode/skills/opencode/` | Symlink or dual-install |
| `hermes-agent` | `~/.hermes/skills/autonomous-ai-agents/hermes-agent/` | N/A | Hermes-only |
| `karpathy-guidelines` | `~/.hermes/skills/software-development/karpathy-guidelines/` | `~/.config/opencode/skills/karpathy-guidelines/` | Symlink or dual-install |
| `opencode-plan-build-orchestrator` | `~/.hermes/skills/autonomous-ai-agents/opencode-plan-build-orchestrator/` | `~/.config/opencode/skills/` | Hermes-only (orchestrator runs in Hermes) |
| `coding-agents-docs-guideline` | `~/.hermes/skills/software-development/coding-agents-docs-guideline/` | `~/.config/opencode/skills/coding-agents-docs-guideline/` | Symlink or dual-install |
| `hermes` (delegation) | N/A | N/A | Terminal tool — OpenCode→Hermes uses `HERMES_DEFAULT_MODEL`; Hermes→subagent uses `HERMES_DELEGATION_MODEL` |

### Host vs. Docker container differences

| Aspect | Docker container | Host |
|--------|-----------------|------|
| Skill source | Pre-baked in volume at build time | Cloned from GitHub or symlinked |
| Update mechanism | Rebuild container image | `git pull` in skill directory |
| Path isolation | Container-private `/home/hermeswebui/.hermes/skills/` | Shared user `$HOME` — no isolation |
| OpenCode visibility | Separate container with its own `~/.config/opencode/skills/` | Same filesystem — symlinks work directly |
| Skill loading | Hermes searches `skill_root` recursively | Same recursive discovery |

### Skill YAML frontmatter

Every `SKILL.md` carries YAML frontmatter for Hermes skill discovery:

```yaml
---
name: coding-agents-docs-guideline
description: Use when creating, editing, or reviewing files in docs/ directory.
version: 1.0.0
author: bachkukkik
license: MIT
metadata:
  hermes:
    tags: [docs, documentation, style-guide]
    related_skills: [codebase-audit]
---
```

Hermes discovers skills by parsing this frontmatter. The `name` field is the canonical skill identifier used in `skill_view()` and `delegate_task` calls.

## Verification

```bash
# Verify Hermes skill discovery
hermes skill list 2>/dev/null | head -20

# Verify specific skills are loadable
hermes skill info opencode-plan-build-orchestrator
hermes skill info coding-agents-docs-guideline

# Verify OpenCode skill directory
ls -la ~/.config/opencode/skills/

# Verify symlink integrity
test -L ~/.config/opencode/skills/opencode && echo "opencode symlink OK" || echo "opencode symlink MISSING"

# Verify skill frontmatter is valid YAML
for skill in ~/.hermes/skills/*/*/SKILL.md; do
    python3 -c "
import yaml
with open('$skill') as f:
    content = f.read()
if content.startswith('---'):
    _, fm, _ = content.split('---', 2)
    yaml.safe_load(fm)
    print(f'  OK: $skill')
" 2>/dev/null || echo "  FAIL: $skill"
done
```

## What Works

- Hermes discovers skills recursively from `~/.hermes/skills/` with valid YAML frontmatter
- Symlinks between Hermes and OpenCode skill directories provide single-source-of-truth skill files
- Skill frontmatter parsing supports `name`, `description`, `version`, `author`, `license`, and `metadata` fields
- `skill_view()` loads skill content for use in agent prompts and subagent delegation
- `delegate_task` passes skill names to subagents for autonomous loading

## What Fails

- **Symlink breakage after git operations:** If a symlinked skill directory is replaced by `git clone` (rather than updated in-place with `git pull`), the symlink breaks and must be recreated.
- **Missing frontmatter:** A `SKILL.md` file without YAML frontmatter is invisible to Hermes skill discovery — the skill will not appear in `hermes skill list`.
- **OpenCode path mismatch:** OpenCode versions may expect different skill directory structures. A symlink that works for one version may break after an OpenCode update.

## Resolution

- **Symlink breakage:** Use `git pull --ff-only` instead of re-cloning. Wrap clone operations in a function that checks for existing directories and updates in-place.
- **Missing frontmatter:** Ensure every `SKILL.md` starts with `---` delimited YAML containing at minimum `name:` and `description:`. Run the YAML validation loop above as a pre-commit check.
- **OpenCode path mismatch:** Pin OpenCode to a known version and document the expected skill directory structure. After an OpenCode update, re-verify skill discovery with `opencode skill list`.

## Verdict

The symlink-based cross-agent skill sharing approach is lightweight and works well for host installations where both agents share a filesystem. The YAML frontmatter convention provides a clean discovery mechanism for Hermes. The primary fragility is symlink lifecycle management during git updates, which the `clone_or_update()` pattern addresses.
