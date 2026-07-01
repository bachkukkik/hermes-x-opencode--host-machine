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
   - `provider.opencode` with `{env:OPENCODE_API_KEY}` (free Zen auth)
   - top-level `model` = `opencode/deepseek-v4-flash-free` (FREE — saves quota)
   - `provider.litellm.models` refreshed from discovered models
   - **preserves** all existing blocks (permission deny-list, plugins, agent
     build/plan, server, experimental)
3. **Hermes config overlay** — generates a `custom_providers` entry with a
   static `models:` map (Form B schema) listing all discovered models.
4. **auth.json staging** — seeds OpenCode credential store with both provider
   keys.

All output goes to `~/.hermes/host-config-gen/staging/`. **Live configs are
never touched.**

## Usage

```bash
# Dry-run: generate staging + run validation + verify no live files changed
bash ~/.hermes/host-config-gen/generate.sh --dry-run

# Generate staging only
bash ~/.hermes/host-config-gen/generate.sh
```

## Applying the staging output (manual step)

The generator only writes to staging. To apply:

```bash
STAGING=~/.hermes/host-config-gen/staging

# 1. Back up live configs
cp ~/.config/opencode/opencode.jsonc{,.bak}
cp ~/.hermes/config.yaml{,.bak}
cp ~/.local/share/opencode/auth.json{,.bak}

# 2. Apply (review the diffs first!)
cp "$STAGING/opencode.jsonc" ~/.config/opencode/opencode.jsonc
cp "$STAGING/config-hermes-overlay.yaml" ~/.hermes/config.yaml
cp "$STAGING/auth.json" ~/.local/share/opencode/auth.json

# 3. Set the env var for {env:OPENCODE_API_KEY} resolution
export OPENCODE_API_KEY="$OPENCODE_ZEN_API_KEY"
# Or add to ~/.hermes/.env:
#   echo 'OPENCODE_API_KEY=<same-value-as-OPENCODE_ZEN_API_KEY>' >> ~/.hermes/.env

# 4. Verify
opencode run --model opencode/deepseek-v4-flash-free -q "say hello"
hermes config check
```

## Strict requirement: free Zen model

OpenCode defaults to `opencode/deepseek-v4-flash-free` so that Hermes can
delegate coding tasks via the `opencode` skill **without burning paid token
quota**. The credential is `OPENCODE_ZEN_API_KEY` (already in `~/.hermes/.env`).
The `{env:OPENCODE_API_KEY}` ref in `opencode.jsonc` must resolve to the same
value — export it or add it to `.env`.

## Environment variables

| Variable | Purpose | Source |
|----------|---------|--------|
| `OPENCODE_ZEN_API_KEY` | OpenCode Zen free models credential | `~/.hermes/.env` |
| `OPENCODE_API_KEY` | Resolves `{env:OPENCODE_API_KEY}` in opencode.jsonc | Must = `OPENCODE_ZEN_API_KEY` |
| `OPENAI_API_KEY` | Resolves `{env:OPENAI_API_KEY}` (litellm provider) | `~/.hermes/.env` or config.yaml `model.api_key` |
| `OPENAI_BASE_URL` | OpenAI-compatible endpoint URL (default `http://localhost:4000`) | env override |

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
├── generate.sh                    # main orchestrator (--dry-run flag)
├── README.md                      # this file
├── lib/
│   ├── constants.sh               # host paths + defaults
│   ├── model-discovery.sh         # LiteLLM /v1/models discovery + filter
│   ├── config-opencode.sh         # opencode.jsonc MERGE generator
│   ├── config-hermes.sh           # Hermes config.yaml overlay generator
│   └── env-auth.sh                # env resolution + auth.json staging
└── staging/                       # output (gitignored — review before apply)
    ├── opencode.jsonc             # merged OpenCode config
    ├── config-hermes-overlay.yaml # merged Hermes config
    ├── auth.json                  # OpenCode credential store
    └── opencode-merge-summary.txt # diff summary
```
