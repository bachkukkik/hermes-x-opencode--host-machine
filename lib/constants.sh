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

# --- GitHub CLI / git auth ----------------------------------------------------
# `gh` auto-reads GH_TOKEN; accept GITHUB_TOKEN as an alias so either env var works.
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
export GH_TOKEN

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

# Optional proxy-wide small-model default (mirrors OPENAI_DEFAULT_MODEL). When
# set, it feeds the OPENCODE_SMALL_MODEL chain resolved in generate.sh AFTER
# .env is sourced, so a .env-only value is honored (see generate.sh).
OPENAI_SMALL_MODEL="${OPENAI_SMALL_MODEL:-}"

# Small model for lightweight OpenCode tasks. Left unresolved here so generate.sh
# can honor a .env-set OPENAI_SMALL_MODEL after .env is sourced. Full chain:
# OPENCODE_SMALL_MODEL -> OPENAI_SMALL_MODEL -> OPENCODE_DEFAULT_MODEL.
OPENCODE_SMALL_MODEL="${OPENCODE_SMALL_MODEL:-}"

# Image-generation model for the Hermes image_gen overlay block (openai provider).
OPENAI_IMAGE_MODEL="${OPENAI_IMAGE_MODEL:-gpt-image-2}"

# --- DCP (dynamic context pruning) compression threshold --------------------
# The @tarquinen/opencode-dcp plugin defaults to a hard 100_000-token
# maxContextLimit regardless of the model's real window, so a 1M-context model
# gets compression-nudged at ~10% fill. We generate a managed dcp.jsonc whose
# compress.maxContextLimit is expressed as "<pct>%" of EACH model's own context
# window (DCP resolves the percentage per active model). This mirrors Hermes'
# HERMES_COMPRESSION_THRESHOLD. Range 0.0–1.0; default 0.76.
OPENCODE_COMPRESSION_THRESHOLD="${OPENCODE_COMPRESSION_THRESHOLD:-0.76}"

# Hermes-side conversation compression threshold. Always baked into the Hermes
# overlay (parity with the upstream Docker reference, which writes it
# unconditionally). Range 0.0–1.0; default 0.76.
HERMES_COMPRESSION_THRESHOLD="${HERMES_COMPRESSION_THRESHOLD:-0.76}"

# Environment variable names referenced by {env:VAR} in opencode.jsonc.
OPENCODE_API_KEY_ENV="OPENCODE_ZEN_API_KEY"
OPENAI_API_KEY_ENV="OPENAI_API_KEY"

# --- Context-length fallback (used by config generators) --------------------
# When a model isn't in the generator's pin table and IS the default model,
# this value is used as its explicit context_length. The hermes-agent also
# self-resolves unknown models at runtime via its own DEFAULT_CONTEXT_LENGTHS
# table / models.dev / endpoint probe.
DEFAULT_CONTEXT_LENGTHS="${DEFAULT_CONTEXT_LENGTHS:-200000}"

# --- Hermes agent autonomy + output cap (baked into config.yaml) ------------
# Values mirror the Docker reference so host and container behave identically.
#
# Main agent tool-calling loop budget → config.yaml `agent.max_turns`. This is
# the loop that prints "Reached maximum iterations (N)"; DISTINCT from
# HERMES_GOAL_MAX_TURNS (/goal cross-turn budget) and
# HERMES_DELEGATION_MAX_ITERATIONS (per-subagent cap). The agent's built-in
# default is 90; raised to 200 so long autonomous runs don't truncate mid-task.
HERMES_AGENT_MAX_TURNS="${HERMES_AGENT_MAX_TURNS:-200}"

# OUTPUT-token cap baked into config.yaml as model.max_tokens (response-length
# ceiling, NOT the context window). Defaults to 262144 so long responses and
# delegation subagents (which inherit the parent max_tokens) aren't truncated by
# a small upstream proxy/provider default (finish_reason='length'). Integer;
# must stay below the model's context window — lower it if a provider rejects it.
HERMES_MAX_TOKENS="${HERMES_MAX_TOKENS:-262144}"

# Approval mode: yolo (approvals off) by default, matching the Docker reference.
# Accepts 1|true|yes|on to enable; set HERMES_YOLO_MODE=0 to keep Hermes'
# interactive approval prompts.
HERMES_YOLO_MODE="${HERMES_YOLO_MODE:-1}"

# --- Hermes web search / tooling backend -------------------------------------
# Web search uses ddgs (keyless, search-only) by default. Pair with an auto/lazy
# extract backend (leave WEB_EXTRACT_BACKEND empty). Backends are lazy-installed
# on first use when allow_lazy_installs=true.
HERMES_WEB_SEARCH_BACKEND="${HERMES_WEB_SEARCH_BACKEND:-ddgs}"
HERMES_WEB_EXTRACT_BACKEND="${HERMES_WEB_EXTRACT_BACKEND:-}"
HERMES_ALLOW_LAZY_INSTALLS="${HERMES_ALLOW_LAZY_INSTALLS:-true}"

# --- Helpers ------------------------------------------------------------------
log()  { printf '[entrypoint] %s\n' "$@" >&2; }
warn() { printf '[entrypoint] WARN: %s\n' "$@" >&2; }

# --- Stale-lib detection ----------------------------------------------------
# Checks whether installed lib files match the repo source. Sourced by
# generate.sh after loading lib modules. Prints a warning when stale.
# Returns 0 (synced), 1 (stale), or 2 (no installed lib).
check_stale_lib() {
    local installed_lib="${HOME}/.hermes/host-config-gen/lib"
    local names=("config-hermes.sh" "constants.sh")
    local repo_hash installed_hash f
    [ -d "$installed_lib" ] || return 2
    for f in "${names[@]}"; do
        repo_hash=$(sha256sum "${LIB_DIR}/${f}" 2>/dev/null | cut -d' ' -f1) || return 2
        installed_hash=$(sha256sum "${installed_lib}/${f}" 2>/dev/null | cut -d' ' -f1) || return 2
        [ "$repo_hash" = "$installed_hash" ] || return 1
    done
    return 0
}
