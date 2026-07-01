# 01 — Architecture

## What

The Host Config Generator is a bare-metal pipeline that discovers models from a LiteLLM proxy and produces merged config overlays for Hermes Agent and OpenCode CLI — without touching live config files.

## Why

- The parent Docker stack auto-generates configs inside a container at boot. A bare-metal host running Hermes and OpenCode natively needs the same model-discovery and config-generation logic, adapted for host paths and persistent state.
- Docker uses OVERWRITE mode (containers regenerate configs from scratch on every boot). The host uses MERGE mode to preserve hand-tuned settings across regeneration cycles.
- Staging-only output eliminates the risk of corrupting live configs during generation. The user reviews diffs and applies manually.

## How

### Staging pipeline

```
LiteLLM /v1/models ──► discover_models() ──► DISCOVERED_MODELS
                                                    │
                         ┌──────────────────────────┼──────────────────────────┐
                         ▼                          ▼                          ▼
              generate_opencode_staging()  generate_hermes_overlay()  generate_auth_staging()
                         │                          │                          │
                         ▼                          ▼                          ▼
                staging/opencode.jsonc  staging/config-hermes-overlay.yaml  staging/auth.json
```

The orchestrator (`generate.sh`) runs four phases sequentially:

1. **Phase 1 — Model discovery:** Queries the LiteLLM proxy, filters non-chat models, deduplicates, and falls back to `OPENAI_DEFAULT_MODEL` when unreachable.
2. **Phase 2 — OpenCode config merge:** Deep-merges discovered models into the existing `opencode.jsonc`, preserving hand-tuned blocks.
3. **Phase 3 — Hermes config overlay:** Builds a Form B `custom_providers` entry with a static models map and carries forward the existing live config.
4. **Phase 4 — Auth staging:** Resolves credentials in-process and seeds `auth.json`.

### MERGE mode vs. Docker OVERWRITE

| Aspect | Docker (reference) | Host (this repo) |
|--------|-------------------|-----------------|
| Config lifecycle | Regenerated every boot | Persistent; generated on demand |
| Live config strategy | OVERWRITE from scratch | MERGE — preserve existing blocks |
| Paths | `/home/hermeswebui/` (container) | `$HOME/.hermes/`, `$HOME/.config/opencode/` |
| Network | `host.docker.internal:4000` | `localhost:4000` |
| Safety guarantee | Configs rebuilt cleanly | Staging-only; checksum snapshot proves zero mutation |

### File layout

```
~/.hermes/host-config-gen/
├── generate.sh                    # main orchestrator (--dry-run flag)
├── README.md
├── lib/
│   ├── constants.sh               # host paths + defaults
│   ├── model-discovery.sh         # LiteLLM /v1/models discovery + filter
│   ├── config-opencode.sh         # opencode.jsonc MERGE generator
│   ├── config-hermes.sh           # Hermes config.yaml overlay generator
│   └── env-auth.sh                # env resolution + auth.json staging
└── staging/                       # output (gitignored)
    ├── opencode.jsonc
    ├── config-hermes-overlay.yaml
    ├── auth.json
    ├── discovered-models.txt
    └── opencode-merge-summary.txt
```

### Data flow

All key reads happen **in-process** via Python — the LiteLLM API key, OpenCode Zen key, and OpenAI key are read inside `python3 -` heredocs and never exposed as shell variables. This avoids Hermes secret-redaction mangling keys interpolated into the agent shell.

## Verification

```bash
# Confirm the staging pipeline runs clean
cd ~/.hermes/host-config-gen
bash generate.sh --dry-run

# Verify staging output integrity
python3 -m json.tool staging/opencode.jsonc > /dev/null
python3 -c "import yaml; yaml.safe_load(open('staging/config-hermes-overlay.yaml'))" > /dev/null
python3 -m json.tool staging/auth.json > /dev/null

# Confirm live files are untouched (checksum snapshot)
sha256sum ~/.hermes/config.yaml ~/.config/opencode/opencode.jsonc > /tmp/pre-snapshot
# ... run generate.sh --dry-run ...
sha256sum ~/.hermes/config.yaml ~/.config/opencode/opencode.jsonc > /tmp/post-snapshot
diff /tmp/pre-snapshot /tmp/post-snapshot && echo "No live mutations"
```

## What Works

- Four-phase pipeline produces valid JSON/YAML staging output on every run
- MERGE mode preserves permission, plugin, server, experimental, and agent blocks in opencode.jsonc
- All API keys read in-process via Python — zero shell-variable exposure
- Checksum snapshot in `--dry-run` proves no live config mutation
- Staging directory is completely rebuilt on every run (clean slate)

## What Fails

- **LiteLLM unreachable:** Model discovery returns empty; the pipeline falls back to `OPENAI_DEFAULT_MODEL` only.
- **Missing live config:** If `~/.hermes/config.yaml` or `~/.config/opencode/opencode.jsonc` is absent, the generator starts from an empty base — all hand-tuned blocks are lost.
- **Python yaml module missing:** `generate_hermes_overlay()` and `generate_auth_staging()` fail with import errors.

## Resolution

- **LiteLLM unreachable:** Ensure the LiteLLM proxy is running (`curl http://localhost:4000/health`). Set `OPENAI_BASE_URL` if the proxy is remote. The fallback to `zai/glm-5.2` ensures basic functionality survives.
- **Missing live config:** Run `hermes config init` or `opencode init` before the generator. The generator creates a valid output even without live configs, but it will lack your custom blocks.
- **Python yaml module missing:** Install with `pip install pyyaml`. The install script (`install.sh`) checks for this prerequisite and aborts if missing.

## Verdict

The staging pipeline is functionally equivalent to the Docker reference while adding the MERGE mode and staging-only safety guarantees required for a persistent host environment. Key safety (in-process Python reads) and zero-touch live config verification make it safe for repeated use.
