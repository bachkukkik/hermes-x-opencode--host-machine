#!/usr/bin/env python3
"""Write OPENAI_DEFAULT_MODEL into a .env file from live config."""
import sys, os, yaml

target = sys.argv[1] if len(sys.argv) > 1 else None
if not target or not os.path.isfile(target):
    sys.exit(0)

# Precedence: live config model.default > OPENAI_DEFAULT_MODEL env > zai/glm-5.2
new_model = ""
cfg_path = os.path.expanduser("~/.hermes/config.yaml")
try:
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f) or {}
    new_model = cfg.get("model", {}).get("default", "")
except Exception:
    pass
new_model = new_model or os.environ.get("OPENAI_DEFAULT_MODEL", "") or "zai/glm-5.2"

# Read .env, update OPENAI_DEFAULT_MODEL line
with open(target) as f:
    lines = f.readlines()

updated = False
for i, line in enumerate(lines):
    if line.startswith("OPENAI_DEFAULT_MODEL="):
        lines[i] = f"OPENAI_DEFAULT_MODEL={new_model}\n"
        updated = True
        break

if updated:
    with open(target, "w") as f:
        f.writelines(lines)
    print(f"OPENAI_DEFAULT_MODEL={new_model}", file=sys.stderr)
