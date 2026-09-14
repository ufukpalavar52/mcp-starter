#!/usr/bin/env bash
#
# Clones the six service repositories next to this one, or updates them if they are
# already there.
#
# Optional. Anybody who has the sources somewhere else points MCP_*_PATH at them in .env
# and never runs this; what it saves is six git commands and the chance of mistyping one.
#
#   ./clone.sh                     into the parent directory
#   ./clone.sh ~/work/mcp          into a directory of your choosing
#   ./clone.sh --ssh               over SSH rather than HTTPS
#
# It writes .env for you when there is none, pointing at wherever the clones landed. An
# existing .env is left alone: it holds passwords, and a setup script that overwrites
# credentials is a setup script nobody runs twice.

set -euo pipefail

OWNER="${MCP_GITHUB_OWNER:-ufukpalavar52}"
REPOS=(mcp-gateway mcp-config mcp-server mcp-action mcp-cipher mcp-panel)

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$(cd "$here/.." && pwd)"
scheme="https"

while [ $# -gt 0 ]; do
    case "$1" in
        --ssh)  scheme="ssh" ;;
        -h|--help)
            sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 2 ;;
        *)
            mkdir -p "$1"
            target="$(cd "$1" && pwd)" ;;
    esac
    shift
done

url_for() {
    if [ "$scheme" = "ssh" ]; then
        echo "git@github.com:$OWNER/$1.git"
    else
        echo "https://github.com/$OWNER/$1.git"
    fi
}

echo "Repositories go into $target"
echo

failed=()
for repo in "${REPOS[@]}"; do
    path="$target/$repo"

    if [ -d "$path/.git" ]; then
        # Pulled with --ff-only: this script's job is to fetch code, not to decide what
        # to do about local commits. A merge it started and could not finish would leave
        # somebody's working tree in a state they did not ask for.
        printf '  %-13s ' "$repo"
        if git -C "$path" pull --ff-only --quiet 2>/dev/null; then
            echo "updated"
        else
            echo "left alone (local changes, or diverged)"
        fi
        continue
    fi

    if [ -e "$path" ]; then
        printf '  %-13s exists and is not a git repository; skipped\n' "$repo"
        failed+=("$repo")
        continue
    fi

    printf '  %-13s ' "$repo"
    if git clone --quiet "$(url_for "$repo")" "$path" 2>/dev/null; then
        echo "cloned"
    else
        echo "FAILED"
        failed+=("$repo")
    fi
done

echo

# .env, only when there is not one already.
if [ -f "$here/.env" ]; then
    echo ".env is already there; not touched."
else
    cp "$here/.env.example" "$here/.env"
    for repo in "${REPOS[@]}"; do
        var="MCP_$(echo "${repo#mcp-}" | tr '[:lower:]-' '[:upper:]_')_PATH"
        # In-place edit, portable between BSD and GNU sed: -i takes an argument on one
        # and not the other, so neither form is written.
        tmp="$(mktemp)"
        sed "s|^$var=.*|$var=$target/$repo|" "$here/.env" > "$tmp" && mv "$tmp" "$here/.env"
    done
    echo "Wrote .env with the paths filled in. The credentials in it are still blank:"
    echo "  CONFIG_PASSWORD, DB_PASSWORD, REDIS_PASSWORD, QUEUE_PASSWORD,"
    echo "  JWT_SECRET_KEY, MCP_CIPHER_KEY_V1, MCP_CIPHER_TOKEN"
    echo
    echo "  openssl rand -base64 32     # for the two keys"
    echo
    echo "Set MCP_ADMIN_EMAIL and MCP_ADMIN_PASSWORD too, or there will be nobody to log"
    echo "in as."
fi

if [ ${#failed[@]} -gt 0 ]; then
    echo
    echo "Did not get: ${failed[*]}"
    exit 1
fi

echo
echo "Then: docker compose up -d"
