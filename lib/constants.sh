# lib/constants.sh — host paths + user variables (sourced by generate.sh)
#
# Host-level adaptation of the Docker constants.sh. Docker used
# /home/hermeswebui + host.docker.internal; host uses $HOME + localhost.

# --- Hermes paths -----------------------------------------------------------
export HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
CONFIG="${HERMES_HOME}/config.yaml"
AGENT_DIR="${HERMES_HOME}/hermes-agent"
HERMES_ENV="${HERMES_HOME}/.env"

# --- OpenCode paths ---------------------------------------------------------
OPENCODE_CONFIG="${HOME}/.config/opencode/opencode.jsonc"
OPENCODE_DCP_CONFIG="${HOME}/.config/opencode/dcp.jsonc"
OPENCODE_AUTH="${HOME}/.local/share/opencode/auth.json"
OPENCODE_USER="${USER:-$(id -un 2>/dev/null || echo "${USER}")}"
OPENCODE_USER_HOME="${HOME}"

# --- Generator / staging paths ----------------------------------------------
GEN_DIR="${HERMES_HOME}/host-config-gen"
LIB_DIR="${LIB_DIR:-${GEN_DIR}/lib}"
STAGING_DIR="${GEN_DIR}/staging"
STAGING_OPENCODE="${STAGING_DIR}/opencode.jsonc"
STAGING_HERMES_OVERLAY="${STAGING_DIR}/config-hermes-overlay.yaml"
STAGING_HERMES_MERGER="${STAGING_DIR}/merge_hermes_overlay.py"
STAGING_AUTH="${STAGING_DIR}/auth.json"
STAGING_DIFF="${STAGING_DIR}/opencode-merge-summary.txt"
STAGING_MODELS="${STAGING_DIR}/discovered-models.txt"
STAGING_DCP="${STAGING_DIR}/dcp.jsonc"

# --- OpenAI-compatible endpoint ----------------------------------------------
# Strip any trailing slash; the /v1 suffix is appended by clients. Host uses
# localhost (Docker used host.docker.internal — normalized away on bare metal).
OPENAI_BASE_URL="${OPENAI_BASE_URL:-http://localhost:4000}"
OPENAI_BASE_URL="${OPENAI_BASE_URL%/}"

# --- Model selection defaults ----------------------------------------------
# Fallback model used when LiteLLM is unreachable/empty (EC1) and seeded into
# the discovered list so it is always present.
OPENAI_DEFAULT_MODEL="${OPENAI_DEFAULT_MODEL:-zai/glm-5.2}"

# STRICT USER REQUIREMENT: OpenCode must default to the FREE Zen model so
# Hermes -> OpenCode delegation burns no paid token quota.
OPENCODE_DEFAULT_MODEL="${OPENCODE_DEFAULT_MODEL:-opencode/deepseek-v4-flash-free}"

# Small model for lightweight OpenCode tasks — defaults to OPENCODE_DEFAULT_MODEL.
OPENCODE_SMALL_MODEL="${OPENCODE_SMALL_MODEL:-${OPENCODE_DEFAULT_MODEL}}"

# --- DCP (dynamic context pruning) compression threshold --------------------
# The @tarquinen/opencode-dcp plugin defaults to a hard 100_000-token
# maxContextLimit regardless of the model's real window, so a 1M-context model
# gets compression-nudged at ~10% fill. We generate a managed dcp.jsonc whose
# compress.maxContextLimit is expressed as "<pct>%" of EACH model's own context
# window (DCP resolves the percentage per active model). This mirrors Hermes'
# HERMES_COMPRESSION_THRESHOLD. Range 0.0–1.0; default 0.76.
OPENCODE_COMPRESSION_THRESHOLD="${OPENCODE_COMPRESSION_THRESHOLD:-0.76}"

# Environment variable names referenced by {env:VAR} in opencode.jsonc.
OPENCODE_API_KEY_ENV="OPENCODE_ZEN_API_KEY"
OPENAI_API_KEY_ENV="OPENAI_API_KEY"

# --- Context-length fallback (used by config generators) --------------------
# When a model isn't in the generator's pin table and IS the default model,
# this value is used as its explicit context_length. The hermes-agent also
# self-resolves unknown models at runtime via its own DEFAULT_CONTEXT_LENGTHS
# table / models.dev / endpoint probe.
DEFAULT_CONTEXT_LENGTHS="${DEFAULT_CONTEXT_LENGTHS:-200000}"
