# lib/sync-env.sh — section-based sync: repo .env → ~/.hermes/.env
#
# Hermes itself writes to ~/.hermes/.env (API keys, auto-generated comments).
# Blindly overwriting that file destroys those entries. Instead, we manage a
# DELIMITED SECTION: everything between the begin/end markers is our domain;
# everything outside is Hermes's / the user's.
#
# Workflow:
#   1. Edit .env in the repo (the source of truth for model config).
#   2. Run install.sh or call sync_env_to_hermes directly.
#   3. The managed section in ~/.hermes/.env is replaced with the repo's
#      current managed section. Everything else is untouched.
#
# Markers (must match exactly in both files):
#   >>> hermes-x-opencode-host-config begin >>>
#   <<< hermes-x-opencode-host-config end <<<

sync_env_to_hermes() {
    local src="${1:-${SCRIPT_DIR}/.env}"
    local dst="${HERMES_HOME:-${HOME}/.hermes}/.env"

    if [ ! -f "$src" ]; then
        echo "sync-env: source .env not found at $src — nothing to sync." >&2
        return 1
    fi

    local begin_marker="# >>> hermes-x-opencode-host-config begin >>>"
    local end_marker="# <<< hermes-x-opencode-host-config end <<<"

    # --- Extract the managed section from SOURCE (.env in repo) -------------
    local src_section
    src_section=$(awk "/^${begin_marker//\//\\/}/,/^${end_marker//\//\\/}/" "$src" 2>/dev/null || true)
    if [ -z "$src_section" ]; then
        echo "sync-env: managed section not found in $src (missing markers)." >&2
        echo "sync-env: wrap your config with:" >&2
        echo "  $begin_marker" >&2
        echo "  ..." >&2
        echo "  $end_marker" >&2
        return 1
    fi

    # --- If destination exists, replace managed section; else append -------
    if [ -f "$dst" ]; then
        # Check if destination already has markers
        if grep -qF "$begin_marker" "$dst" 2>/dev/null; then
            # Replace existing managed section
            local tmp
            tmp=$(mktemp)
            awk -v begin="$begin_marker" -v end="$end_marker" -v section="$src_section" '
                BEGIN { in_section=0; replaced=0 }
                $0 == begin  { in_section=1; if (!replaced) { print section; replaced=1 }; next }
                $0 == end    { in_section=0; next }
                !in_section  { print }
                END { if (!replaced) { print ""; print section } }
            ' "$dst" > "$tmp"
            mv "$tmp" "$dst"
            echo "sync-env: updated managed section in $dst"
        else
            # No existing section — append
            echo "" >> "$dst"
            echo "$src_section" >> "$dst"
            echo "sync-env: appended managed section to $dst"
        fi
    else
        # Destination doesn't exist — create with just the managed section
        mkdir -p "$(dirname "$dst")"
        echo "$src_section" > "$dst"
        chmod 600 "$dst"
        echo "sync-env: created $dst with managed section"
    fi

    # Ensure correct permissions
    chmod 600 "$dst" 2>/dev/null || true
}
