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
OPENCODE_AUTH="${HOME}/.local/share/opencode/auth.json"
OPENCODE_USER="${USER:-$(id -un 2>/dev/null || echo "${USER}")}"
OPENCODE_USER_HOME="${HOME}"

# --- Generator / staging paths ----------------------------------------------
GEN_DIR="${HERMES_HOME}/host-config-gen"
LIB_DIR="${GEN_DIR}/lib"
STAGING_DIR="${GEN_DIR}/staging"
STAGING_OPENCODE="${STAGING_DIR}/opencode.jsonc"
STAGING_HERMES_OVERLAY="${STAGING_DIR}/config-hermes-overlay.yaml"
STAGING_HERMES_MERGER="${STAGING_DIR}/merge_hermes_overlay.py"
STAGING_AUTH="${STAGING_DIR}/auth.json"
STAGING_DIFF="${STAGING_DIR}/opencode-merge-summary.txt"
STAGING_MODELS="${STAGING_DIR}/discovered-models.txt"

# --- LiteLLM proxy ----------------------------------------------------------
# Strip any trailing slash; the /v1 suffix is appended by clients. Host uses
# localhost (Docker used host.docker.internal — normalized away on bare metal).
LITELLM_BASE_URL="${LITELLM_BASE_URL:-http://localhost:4000}"
LITELLM_BASE_URL="${LITELLM_BASE_URL%/}"

# --- Model selection defaults ----------------------------------------------
# Fallback model used when LiteLLM is unreachable/empty (EC1) and seeded into
# the discovered list so it is always present.
DEFAULT_MODEL="${DEFAULT_MODEL:-zai/glm-5.1}"

# STRICT USER REQUIREMENT: OpenCode must default to the FREE Zen model so
# Hermes -> OpenCode delegation burns no paid token quota.
OPENCODE_FREE_MODEL="opencode/deepseek-v4-flash-free"

# Environment variable names referenced by {env:VAR} in opencode.jsonc.
OPENCODE_API_KEY_ENV="OPENCODE_API_KEY"
OPENAI_API_KEY_ENV="OPENAI_API_KEY"
