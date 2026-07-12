# Hermes × OpenCode Host Config Generator

A bare-metal "copycat" of the Docker stack's config-generation pipeline
(`volumes_hermes_opencode/build/scripts/`). Discovers models from the LiteLLM
proxy and generates **merged** config overlays for Hermes Agent and OpenCode.

## Origin / Related

This repo is a standalone extraction of the host-level config generator, kept
separate from the Docker stack so it can be cloned and run on a bare-metal host
without the full compose setup. The parent project (Docker stack, volumes, and
build scripts) lives at <https://github.com/bachkukkik/hermes-x-opencode>.

## What it does

1. **Model discovery** — queries `http://localhost:4000/v1/models` (the LiteLLM
   proxy), applies the Docker filter pipeline (drops embed/whisper/tts/image/
   wildcard/etc.), dedupes, and caches the result.
2. **OpenCode config merge** — loads the existing `opencode.jsonc`, injects:
   - `provider.opencode` with `{env:OPENCODE_ZEN_API_KEY}` (free Zen auth)
   - top-level `model` = `opencode/deepseek-v4-flash-free` (FREE — saves quota)
   - `provider.litellm.models` refreshed from discovered models
   - **preserves** all existing blocks (permission deny-list, plugins, agent
     build/plan, server, experimental)
3. **Hermes config overlay** — generates a `custom_providers` entry with a
   static `models:` map (Form B schema) listing all discovered models.
   - Sets `model.provider: custom:litellm` (nested) so Hermes uses the generated custom provider for its active model, and mirrors the models map + credential into a legacy `providers.litellm` block (which the model-switch path reads first).
4. **auth.json staging** — seeds OpenCode credential store with both provider
   keys.

All output goes to `~/.hermes/host-config-gen/staging/`. **Live configs are
never touched.**

## Usage

```bash
# Dry-run: generate staging + run validation + verify no live files changed
bash ~/.hermes/host-config-gen/generate.sh --dry-run

# Generate staging only (no changes to live configs)
bash ~/.hermes/host-config-gen/generate.sh

# Generate + apply to live configs (with .bak backups)
bash ~/.hermes/host-config-gen/generate.sh --apply

# Preview what --apply would do (no writes)
bash ~/.hermes/host-config-gen/generate.sh --apply --dry-run
```

### In-repo usage (development)

For development and iteration, run `generate.sh` directly from the repo root instead of the installed path:

```bash
# From the repo root:
bash generate.sh --dry-run     # preview
bash generate.sh --apply       # deploy to live paths (with .bak backups)
```

> **Note:** `generate.sh` sources `${SCRIPT_DIR}/.env` internally, so you do **not** need to `source .env` in your shell first. All credentials from `.env` are read at generation time and inlined into the generated config files — nothing is exported into your shell environment.

## Applying configs

The `--apply` flag copies staging output to live paths with automatic
`.bak` backups.

| Staging file | Live destination |
|---|---|
| `staging/opencode.jsonc` | `~/.config/opencode/opencode.jsonc` |
| `staging/config-hermes-overlay.yaml` | `~/.hermes/config.yaml` |
| `staging/auth.json` | `~/.local/share/opencode/auth.json` |

## Strict requirement: free Zen model

OpenCode defaults to `opencode/deepseek-v4-flash-free` so that Hermes can
delegate coding tasks via the `opencode` skill **without burning paid token
quota**. The credential is `OPENCODE_ZEN_API_KEY` (in the repo `.env` or
`~/.hermes/.env`). Its literal value is **inlined** into `opencode.jsonc` and
seeded into `auth.json` at generation time, so opencode resolves it with no
environment variable set.

## Credentials are inlined — no shell environment, no pollution

`opencode` and `hermes` run from **any directory with no environment variables
set**. At generation time the generator reads the credentials from `.env`
(in-process) and bakes their literal values into the generated config files:

| Credential | Inlined into |
|---|---|
| `OPENAI_API_KEY` | `opencode.jsonc` (`provider.litellm`/`llama_cpp`), `auth.json` (`litellm`), `config.yaml` |
| `OPENCODE_ZEN_API_KEY` | `opencode.jsonc` (`provider.opencode`), `auth.json` (`opencode`) |

Because nothing is exported into your shell, this repo **never mutates your
`~/.bashrc`/`~/.zshrc` and never leaks secrets into other repos' environments**.
There is no `export-env.sh` and no shell/rc-file integration.

> **Upgrading from an older version?** Run `bash install.sh` — it purges the
> legacy `export-env.sh` helper and removes any `hermes host-config-gen env
> bridge` block previously added to your rc files (backing them up first).

## Environment variables

| Variable | Purpose | Default |
|----------|---------|--------|
| `OPENAI_API_KEY` | LiteLLM proxy API key for model discovery and litellm provider | required (in ~/.hermes/.env or config.yaml) |
| `OPENAI_BASE_URL` | OpenAI-compatible endpoint URL | http://localhost:4000 |
| `OPENAI_DEFAULT_MODEL` | Fallback model when LiteLLM unreachable; controls model.default/model.name | zai/glm-5.2 |
| `HERMES_DEFAULT_MODEL` | Override for Hermes active model (overrides OPENAI_DEFAULT_MODEL) | unset |
| `OPENCODE_DEFAULT_MODEL` | Free Zen model for OpenCode delegation tasks | opencode/deepseek-v4-flash-free |
| `OPENCODE_AGENT_MODEL` | Agent build/plan model for OpenCode subagents | same as OPENCODE_DEFAULT_MODEL |
| `OPENCODE_SMALL_MODEL` | Small model for lightweight OpenCode tasks | same as OPENCODE_DEFAULT_MODEL |
| `OPENCODE_FALLBACK_MODEL` | Comma-separated ordered fallback chain for opencode-runtime-fallback plugin | unset |
| `OPENCODE_ZEN_API_KEY` | OpenCode Zen free models credential + {env:OPENCODE_ZEN_API_KEY} resolution | required (in ~/.hermes/.env) |
| `HERMES_YOLO_MODE` | When set to 1, emits approvals.mode:off in staging overlay | unset |
| `HERMES_DELEGATION_MAX_ITERATIONS` | Max iterations for delegated subagent conversations | 50 |
| `HERMES_DELEGATION_MODEL` | Model for delegated subagent conversations (overrides parent model) | unset (inherits parent) |
| `HERMES_DELEGATION_PROVIDER` | Provider for delegated subagent conversations | unset (inherits parent) |
| `HERMES_GOAL_MAX_TURNS` | Max turns for goal-mode tasks | 50 |
| `HERMES_COMPRESSION_THRESHOLD` | Context compression threshold (0.0-1.0) | unset |
| `OPENCODE_COMPRESSION_THRESHOLD` | DCP compress point as fraction of each model's context window; written to managed `dcp.jsonc` as `compress.maxContextLimit: "<pct>%"` | 0.76 |

## Edge cases handled

| EC | Description | Mitigation |
|----|-------------|------------|
| EC1 | LiteLLM unreachable / empty model list | Falls back to `OPENAI_DEFAULT_MODEL` (zai/glm-5.2) |
| EC2 | Key redaction in agent shell | All key reads happen in-process via python3; keys never round-trip through shell variables |
| EC3 | Zen auth failure | OpenCode runtime-fallback plugin handles it; provider config is correct |
| EC4 | Both providers absent | Generator skips cleanly, staging files still written with available data |
| EC5 | Existing config clobbered | MERGE mode: preserves all non-target keys in opencode.jsonc; Hermes overlay carries forward all existing sections |
| EC6 | OPENAI_API_KEY not in .env | Falls back to `model.api_key` from config.yaml |
| EC7 | OpenCode 1.14.48 schema | `{env:VAR}` + provider shapes validated against installed version |

## File layout

```
~/.hermes/host-config-gen/
├── generate.sh                    # main orchestrator (--apply, --dry-run flags)
├── README.md                      # this file
├── lib/
│   ├── constants.sh               # host paths + defaults
│   ├── model-discovery.sh         # LiteLLM /v1/models discovery + filter
│   ├── config-opencode.sh         # opencode.jsonc MERGE generator
│   ├── config-hermes.sh           # Hermes config.yaml overlay generator
│   ├── env-auth.sh                # env resolution + auth.json staging
│   ├── sync-env.sh                # syncs repo .env managed block into ~/.hermes/.env
│   └── validate-zen.sh            # validates OPENCODE_ZEN_API_KEY presence
└── staging/                       # output (gitignored — review before apply)
    ├── opencode.jsonc             # merged OpenCode config
    ├── opencode-fallback.jsonc    # generated fallback OpenCode config
    ├── config-hermes-overlay.yaml # merged Hermes config
    ├── auth.json                  # OpenCode credential store
    └── opencode-merge-summary.txt # diff summary
```
