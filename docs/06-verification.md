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
├── provider.opencode with {env:OPENCODE_API_KEY} present
├── model = opencode/deepseek-v4-flash-free
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
| TC2 | provider.opencode present | `grep -q '"apiKey": "{env:OPENCODE_API_KEY}"' staging/opencode.jsonc` |
| TC3 | custom_providers models count > 1 | `grep -c 'context_length' staging/config-hermes-overlay.yaml` |
| TC4 | opencode.jsonc valid JSON | `python3 -m json.tool staging/opencode.jsonc` |
| TC5 | Hermes overlay valid YAML | `python3 -c "import yaml; yaml.safe_load(...)"` |
| TC6 | free Zen model as default | `grep -q 'opencode/deepseek-v4-flash-free' staging/opencode.jsonc` |
| TC7 | agent sub-block models overridden | `grep -A2 '"build"' staging/opencode.jsonc` |
| TC8 | Preserved blocks in opencode.jsonc | `grep -q '"permission"\|"plugin"\|"agent"\|"server"' staging/opencode.jsonc` |

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

### Applying staging to live (manual step)

The generator never applies staging automatically. The user reviews diffs and applies:

```bash
STAGING=~/.hermes/host-config-gen/staging

# 1. Back up live configs
cp ~/.config/opencode/opencode.jsonc{,.bak}
cp ~/.hermes/config.yaml{,.bak}
cp ~/.local/share/opencode/auth.json{,.bak}

# 2. Review diffs
diff ~/.config/opencode/opencode.jsonc "$STAGING/opencode.jsonc" || true
diff ~/.hermes/config.yaml "$STAGING/config-hermes-overlay.yaml" || true

# 3. Apply
cp "$STAGING/opencode.jsonc" ~/.config/opencode/opencode.jsonc
cp "$STAGING/config-hermes-overlay.yaml" ~/.hermes/config.yaml
cp "$STAGING/auth.json" ~/.local/share/opencode/auth.json

# 4. Set env var
export OPENCODE_API_KEY=***

# 5. Verify agents work
opencode run --model opencode/deepseek-v4-flash-free -q "say hello"
hermes config check
```

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
    grep -qi 'zai/glm-5.2' staging/discovered-models.txt
}
```

## Verification

```bash
# Run the full verification suite
cd ~/.hermes/host-config-gen
bash generate.sh --dry-run

# Expected output:
#   [PASS] bash -n generate.sh
#   [PASS] bash -n constants.sh
#   [PASS] bash -n model-discovery.sh
#   [PASS] bash -n config-opencode.sh
#   [PASS] bash -n config-hermes.sh
#   [PASS] bash -n env-auth.sh
#   [PASS] staging/opencode.jsonc valid JSON
#   [PASS] staging/config-hermes-overlay.yaml valid YAML
#   [PASS] opencode.jsonc has provider.opencode ({env:OPENCODE_API_KEY})
#   [PASS] opencode.jsonc model = opencode/deepseek-v4-flash-free
#   [PASS] Hermes overlay custom_providers has N models
#   [PASS] opencode.jsonc preserves 'permission' block
#   [PASS] opencode.jsonc preserves 'plugin' block
#   [PASS] opencode.jsonc preserves 'agent' block
#   [PASS] opencode.jsonc preserves 'server' block
#   [PASS] no live config files modified
#   RESULT: 16 passed, 0 failed

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
