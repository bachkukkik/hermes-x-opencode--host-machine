# 07 — Installation & Deployment

## What

`install.sh` deploys the generator from the git-tracked repo to `~/.hermes/host-config-gen/` via flat file copy, creating a two-tier model where the repo is the source of truth and the deployed copy is the runtime.

## Why

- **Separation of concerns:** The repo is the versioned development environment; the deployed copy is the stable runtime. Changes are iterated in the repo and only propagated on explicit install.
- **In-repo iteration:** Developers can edit and run `bash generate.sh` from the repo without touching the live system. The deployed copy receives changes only when `install.sh` is run.
- **Docker parity without containers:** The two-tier model mirrors the Docker stack's build→runtime separation using file copies instead of container images — no overhead, same safety boundary.
- **Portable .env sourcing:** Cross-reference [docs/02](02-config-generation.md) for the portable `.env` pattern. The deployed copy carries its own `.env` colocated with `generate.sh`, enabling clean install-to-deploy workflows.

## How

### Two-tier deployment model

```
repo: ~/Archives/.../hermes-x-opencode--host-machine/
  ├── generate.sh          ← source of truth (git-tracked)
  ├── lib/*.sh
  ├── .env
  │
  │  bash install.sh [--no-run]
  │  (flat cp: generate.sh, README.md, lib/*.sh, .env)
  ▼
deployed: ~/.hermes/host-config-gen/
  ├── generate.sh          ← runtime copy
  ├── lib/*.sh
  ├── .env                 ← colocated (portable sourcing)
  └── staging/             ← output (gitignored)
```

### install.sh operation

| Aspect | Detail |
|--------|--------|
| Destination constant | `DEST="${HOME}/.hermes/host-config-gen"` (line 14) |
| Copied files | `generate.sh`, `README.md`, `lib/*.sh`, `.env` (lines 80–85) |
| Prerequisite checks | `bash`, `python3`, `pyyaml` (required — aborts if missing); `hermes`, `opencode` (optional — warns if absent) |
| Default behavior | Install, then run `generate.sh --dry-run` as post-install validation |
| `--no-run` flag | Install only — skip the generator run. Used for deploy-only workflows or CI steps |
| `--help` flag | Prints usage from script header comments |
| bash -n verification | Runs `bash -n` on all deployed scripts after copy (lines 101–109) |
| sync-env.sh call | Sources `lib/sync-env.sh` and calls `sync_env_to_hermes()` to sync the managed `.env` section to `~/.hermes/.env` (lines 90–93) |

### sync-env.sh (summary)

The `sync_env_to_hermes()` function manages a delimited section in `~/.hermes/.env`, replacing only the block controlled by the repo while preserving everything else — Hermes auto-generated entries, user-added keys, and third-party tool configs. Full mechanics are documented in [docs/02](02-config-generation.md).

### In-repo vs. installed workflows

| Aspect | In-repo (development) | Installed (production) |
|--------|----------------------|----------------------|
| Script location | `<repo>/generate.sh` | `~/.hermes/host-config-gen/generate.sh` |
| .env source | `<repo>/.env` | Colocated `.env` in deployed directory |
| Command | `source .env && bash generate.sh` | `bash ~/.hermes/host-config-gen/generate.sh` |
| Workspace | Any git branch, uncommitted changes | Stable deployment, git-agnostic |
| Best for | Iteration, testing, debugging | Daily use, automation, CI |

## Verification

```bash
# Confirm deployed copy matches repo entrypoint
diff generate.sh ~/.hermes/host-config-gen/generate.sh

# Check deployed lib/ freshness (all files)
diff -r lib/ ~/.hermes/host-config-gen/lib/

# Test prerequisite checks pass (should exit 0)
bash install.sh --no-run

# Full redeploy + validate recipe
bash install.sh --no-run && bash ~/.hermes/host-config-gen/generate.sh --dry-run
```

## What Works

- **Idempotent installs:** Re-running `install.sh` overwrites deployed files cleanly — the operation is always safe to repeat.
- **Portable .env:** The deployed copy sources its own colocated `.env`, so `generate.sh` works from any deployment path without hardcoded home-directory references.
- **Post-install validation:** `bash -n` syntax checking catches shell errors immediately after deployment. The default dry-run run catches runtime errors before they reach production.
- **`--no-run` isolation:** Deploy-only mode enables scripted verification pipelines where the generator should not execute (e.g., CI steps that check deployment integrity without a live LiteLLM endpoint).

## What Fails

- **Stale-deployed-copy pitfall:** Editing only `lib/*.sh` (not `generate.sh`) leaves the deployed `lib/` stale. A naive `diff generate.sh` passes because the entrypoint is unchanged, but verification runs against the old `lib/` code. **Symptom:** Silently-wrong output — no error, the new feature is simply absent from staging output. **Root cause:** `lib/` files are deployed independently from `generate.sh`; a diff of only the entrypoint misses the stale library. **Fix:** Always run `install.sh --no-run` before `generate.sh --dry-run` when any `lib/` file changed. The redeploy is fast (<1s for shell scripts).
- **Forgetting `--no-run` in CI:** The default `install.sh` runs the generator, which may fail in environments without a reachable LiteLLM endpoint. Use `--no-run` for deploy-only CI steps.
- **Editing deployed copy directly:** Changes to `~/.hermes/host-config-gen/` are lost on the next `install.sh`. Always edit in the repo and redeploy.
- **LIB_DIR resolution (constants.sh):** When running `bash generate.sh` from the repo directory, `constants.sh` uses `LIB_DIR="${LIB_DIR:-${GEN_DIR}/lib}"` (parameter expansion), so `lib/` modules load from the repo's `lib/` directory by default. In-repo iteration of `lib/*.sh` changes works directly — run `bash generate.sh --dry-run` without installing first. The deployed copy's `lib/` is only used when `LIB_DIR` is pre-set by `install.sh`, which exports it before calling the generator.

## Resolution

The canonical workflows for iteration are:

**In-repo (lib/ or generate.sh changes):** `edit repo → generate.sh --dry-run → review staging → generate.sh --apply`  
**Deployed (production):** `edit repo → install.sh --no-run → generate.sh --dry-run → review staging → generate.sh --apply`

- **For stale-deployed-copy (deployed workflow):** When running the deployed copy after editing `lib/`, run `bash install.sh --no-run` first to redeploy. This ensures the deployed copy reflects all repo changes. For in-repo iteration, no install step is needed — `bash generate.sh` directly sources the repo's `lib/`.
- **For CI deployment:** Pass `--no-run` to `install.sh` to perform a deploy-only step without requiring a live LiteLLM endpoint.
- **For accidental deployed-copy edits:** Re-run `install.sh` from the repo to restore the deployed copy to its source-of-truth state. Any changes made directly in `~/.hermes/host-config-gen/` are discarded.

## Verdict

The two-tier model trades a small cognitive load — remembering to redeploy for deployed-copy runs — for clean separation of versioned source and runtime. In-repo iteration removes the stale-deployed-copy pitfall for development; the `install.sh --no-run` recipe addresses it for the deployed workflow.
