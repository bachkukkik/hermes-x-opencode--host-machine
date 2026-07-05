# 06 — Verification

## What

Verification is a multi-layered process that confirms the config generator produces valid, safe output — from bash syntax checks through live-file mutation proofs to end-to-end agent delegation tests.

## Why

- The staging-only guarantee is the project's core safety property. Verification must prove that live config files are never modified by the generator.
- Generated configs feed directly into production agents. Syntax errors in JSON/YAML or semantic errors (missing providers, wrong model references) cause agent startup failures.
- The Docker reference stack runs identical verification in CI. The host pipeline must match or exceed this standard.

## How

### Verification layers

```
Layer 1: Static checks
├── bash -n on all *.sh scripts
├── python3 -m json.tool on staging/opencode.jsonc
└── python3 yaml.safe_load() on staging/config-hermes-overlay.yaml

Layer 2: Content assertions
├── provider.opencode with {env:OPENCODE_ZEN_API_KEY} present
├── model = $OPENCODE_DEFAULT_MODEL (dynamic)
├── custom_providers has >1 model entries
└── Preserved blocks (permission, plugin, agent, server) present

Layer 3: Safety proof (--dry-run only)
├── Pre-generation checksum snapshot of all live files
├── Post-generation checksum comparison
└── Zero-mutation assertion

Layer 4: End-to-end tests (bats)
├── Full generate.sh --dry-run exit code 0
├── Staging output valid JSON/YAML
├── Model list non-empty
└── Agent delegation smoke tests
```

### --dry-run mode

```bash
# generate.sh --dry-run internal flow
snapshot_live_checksums()          # sha256sum of config.yaml, opencode.jsonc, .env, auth.json
    │
    ▼
Phase 1-4: discover + generate     # normal pipeline — writes only to staging/
    │
    ▼
Validation suite                    # 10+ assertion checks
    │
    ▼
verify_live_checksums()            # compare post-run checksums against snapshot
    │
    ▼
PASS/FAIL report                   # exit code 0 only if ALL checks pass
```

### bash -n syntax check

All scripts in `lib/` and `generate.sh` are checked:

```bash
for script in generate.sh lib/*.sh; do
    bash -n "$script" || exit 1
done
```

### JSON/YAML validity

```bash
# OpenCode staging config
python3 -m json.tool staging/opencode.jsonc > /dev/null

# Hermes staging config
python3 -c "import yaml; yaml.safe_load(open('staging/config-hermes-overlay.yaml'))" > /dev/null
```

### Content assertions

| Test | Check | Command |
|------|-------|---------|
| TC1 | bash -n on all scripts | `bash -n "$script"` per file |
| TC2 | provider.opencode present | `grep -q '"apiKey": "{env:OPENCODE_ZEN_API_KEY}"' staging/opencode.jsonc` |
| TC3 | custom_providers models count > 1 | `grep -c 'context_length' staging/config-hermes-overlay.yaml` |
| TC4 | opencode.jsonc valid JSON | `python3 -m json.tool staging/opencode.jsonc` |
| TC5 | Hermes overlay valid YAML | `python3 -c "import yaml; yaml.safe_load(...)"` |
| TC6 | OPENCODE_DEFAULT_MODEL as default | `grep -q "$OPENCODE_DEFAULT_MODEL" staging/opencode.jsonc` |
| TC7 | agent sub-block models overridden | `grep -A2 '"build"' staging/opencode.jsonc` |
| TC8 | Preserved blocks in opencode.jsonc | `grep -q '"permission"\|"plugin"\|"agent"\|"server"' staging/opencode.jsonc` |
| TC9 | provider.llama_cpp present with correct npm | `grep -q '"llama_cpp"' staging/opencode.jsonc && grep -q '"@ai-sdk/openai-compatible"' staging/opencode.jsonc` |
| TC10 | provider.llama_cpp.models populated | Python check: `provider.llama_cpp.models` is non-empty dict with `name`+`limit` per entry |

### Checksum snapshot

The `--dry-run` flag takes a pre-generation snapshot and verifies it post-generation:

```bash
# Files protected by the checksum snapshot
~/.hermes/config.yaml
~/.config/opencode/opencode.jsonc
~/.hermes/.env
~/.local/share/opencode/auth.json
```

Any checksum mismatch after generation is a **hard failure** — exit code non-zero.

### Applying staging to live (`--apply`)

After reviewing the staging output, apply to live configs with one command.
The generator automatically creates `.bak` backups before overwriting:

```bash
bash ~/.hermes/host-config-gen/generate.sh --apply
```

Preview what would be copied without writing:

```bash
bash ~/.hermes/host-config-gen/generate.sh --apply --dry-run
```

| Staging file | Live destination |
|---|---|
| `staging/opencode.jsonc` | `~/.config/opencode/opencode.jsonc` |
| `staging/config-hermes-overlay.yaml` | `~/.hermes/config.yaml` |
| `staging/auth.json` | `~/.local/share/opencode/auth.json` |

### Shell integration (--shell-integration)

Appends a guarded sentinel block to `~/.bashrc` (or `~/.zshrc`) that sources `export-env.sh` on every shell startup:

```bash
# >>> hermes host-config-gen env bridge (managed, do not edit) >>>
[ -f "$HOME/.hermes/host-config-gen/export-env.sh" ] && source "$HOME/.hermes/host-config-gen/export-env.sh"
# <<< hermes host-config-gen env bridge <<<
```

**Usage:**

```bash
# Installed path:
bash ~/.hermes/host-config-gen/generate.sh --apply --shell-integration

# In-repo (development):
source .env && bash generate.sh --apply --shell-integration
```

**Idempotency:** Re-running does not duplicate the block. **Rollback:** `--apply --remove-shell-integration` removes it cleanly; no-op if absent. **Verification:** `grep -n 'hermes host-config-gen' ~/.bashrc` to audit.

### bats e2e tests

Planned for Phase 2. The test structure follows the Docker reference:

```bash
#!/usr/bin/env bats

@test "generate.sh --dry-run exits 0" {
    run bash generate.sh --dry-run
    [ "$status" -eq 0 ]
}

@test "staging/opencode.jsonc is valid JSON" {
    run python3 -m json.tool staging/opencode.jsonc
    [ "$status" -eq 0 ]
}

@test "discovered-models.txt is non-empty" {
    [ -s staging/discovered-models.txt ]
}

@test "default model is present in discovery" {
    grep -qi "${OPENCODE_DEFAULT_MODEL}" staging/discovered-models.txt
}
```

## Per-Delegation Model Routing (PR #68)

`HERMES_DELEGATION_MODEL` and `HERMES_DELEGATION_PROVIDER` allow routing subagent conversations to a different model/provider than the parent. When set, these appear in the staging overlay under `delegation:`. This is useful for using a cheaper/faster model for delegated tasks while keeping the parent model unchanged.

## Credential Resolution (PR #66 / CA-30-A)

The auth.json staging follows an **OR guard contract**: the litellm credential seeds when `OPENAI_API_KEY` is set in `~/.hermes/.env` **OR** falls back to the inline `api_key` in `~/.hermes/config.yaml`. Both opencode and litellm providers are independent — an empty `auth.json` is a valid state when the user has not configured either provider yet.

The opencode (Zen) credential seeds from `OPENCODE_ZEN_API_KEY` in `~/.hermes/.env` with no fallback — it must be explicitly configured. This naming aligns with the official Hermes agent convention (hermes config, hermes doctor, opencode-zen provider plugin).

This contract prevents regression where both providers silently fail to seed. The test suite (CRED1-CRED3 in `tests/e2e/22-ctx-pin-and-credentials.bats`) enforces this invariant.

## Verification

```bash
# Run the full verification suite
cd ~/.hermes/host-config-gen
bash generate.sh --dry-run

# Expected output:
#   [PASS] bash -n generate.sh
#   [PASS] bash -n config-hermes.sh
#   [PASS] bash -n config-opencode.sh
#   [PASS] bash -n constants.sh
#   [PASS] bash -n env-auth.sh
#   [PASS] bash -n model-discovery.sh
#   [PASS] bash -n sync-env.sh
#   [PASS] bash -n validate-zen.sh
#   [PASS] staging/opencode.jsonc valid JSON
#   [PASS] staging/config-hermes-overlay.yaml valid YAML
#   [PASS] opencode.jsonc has provider.opencode ({env:OPENCODE_ZEN_API_KEY})
#   [PASS] opencode.jsonc model field present (= <model>)
#   [PASS] Hermes overlay custom_providers has N models
#   [PASS] opencode.jsonc preserves 'permission' block
#   [PASS] opencode.jsonc preserves 'plugin' block
#   [PASS] opencode.jsonc preserves 'agent' block
#   [PASS] opencode.jsonc preserves 'server' block
#   [PASS] opencode.jsonc preserves 'experimental' block
#   [PASS] no live config files modified
# RESULT: 19 passed, 0 failed

# Manual checksum verification (outside --dry-run)
sha256sum ~/.hermes/config.yaml ~/.config/opencode/opencode.jsonc > /tmp/pre
bash generate.sh
sha256sum ~/.hermes/config.yaml ~/.config/opencode/opencode.jsonc > /tmp/post
diff /tmp/pre /tmp/post && echo "Live files untouched" || echo "MUTATION DETECTED"

# Verify staging output integrity
python3 -m json.tool staging/opencode.jsonc > /dev/null && echo "JSON OK"
python3 -c "import yaml; yaml.safe_load(open('staging/config-hermes-overlay.yaml'))" && echo "YAML OK"
python3 -m json.tool staging/auth.json > /dev/null && echo "auth.json OK"
```

## What Works

- `bash -n` catches syntax errors in all shell scripts before execution
- `python3 -m json.tool` validates staged OpenCode config as strict JSON
- `yaml.safe_load()` validates staged Hermes config as valid YAML
- Checksum snapshot proves zero live-file mutation in `--dry-run` mode
- Content assertions verify provider blocks, model references, and preserved blocks
- All 10+ validation tests run automatically as part of every `generate.sh` invocation

## What Fails

- **bash -n false negatives:** `bash -n` catches syntax errors but does not catch runtime errors (undefined variables, command-not-found). Scripts can pass `bash -n` and still fail during execution.
- **JSON validation vs. OpenCode schema:** `python3 -m json.tool` proves valid JSON but does not validate against OpenCode's expected schema. A structurally valid JSON file with wrong key names passes validation but fails at runtime.
- **Checksum false positives on config writes:** If another process (e.g., an editor auto-save, a config sync daemon) writes to a live config file during generation, the checksum snapshot fails even though the generator did not cause the mutation.

## Resolution

- **bash -n false negatives:** Run `generate.sh` (without `--dry-run`) to catch runtime errors. The install script (`install.sh`) runs a full `--dry-run` as a post-install verification step.
- **JSON validation vs. OpenCode schema:** After applying staging, run `opencode run -q "say hello"` for a runtime smoke test. OpenCode reports schema errors on startup. Follow the OpenCode 1.14.48 schema reference for key names.
- **Checksum false positives:** Run `--dry-run` in a quiet environment with no concurrent config editors. If checksums fail, compare timestamps to determine whether the generator or an external process caused the change.

## Verdict

The four-layer verification design (static checks → content assertions → safety proof → e2e tests) provides defense-in-depth for the core safety guarantee. The checksum snapshot is the strongest guarantee — it mathematically proves the generator never touches live files. The primary gap is the absence of bats e2e tests (planned for Phase 2), which would add runtime validation of agent delegation and schema correctness.
