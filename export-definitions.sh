#!/usr/bin/env bash
#
# Writes every definition to definitions/<toolName>.json.
#
# A definition is the one thing in this stack that exists only in the database. The
# services are in git, the schema is in git, the settings are in git — but what a tool
# actually does, which hosts it reaches, and the system prompt that tells a model how to
# use it live in a row somebody edited through a screen. Rebuild from nothing and they are
# gone.
#
# The directory is deliberately ignored by git. An export carries the sealed model key, the
# sealed SSH key and the addresses of real machines: sealed is not the same as safe to
# publish, and a repository is a place things get copied out of. Keep the file, back it up
# where the rest of your secrets live, and do not push it.
#
#   ./export-definitions.sh              uses MCP_ADMIN_* from .env
#   ./export-definitions.sh -o somewhere writes there instead

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/definitions"

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--out) out="$2"; shift ;;
        -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

[ -f "$here/.env" ] || { echo "No .env here; nothing to read credentials from." >&2; exit 1; }
# shellcheck disable=SC1091
set -a; . "$here/.env"; set +a

port="${GATEWAY_PORT:-8080}"
api="http://localhost:${port}/api/v1"

token=$(curl -sf -X POST "$api/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"${MCP_ADMIN_EMAIL}\",\"password\":\"${MCP_ADMIN_PASSWORD}\"}" \
    | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p')

if [ -z "$token" ]; then
    echo "Could not sign in as ${MCP_ADMIN_EMAIL} on port ${port}." >&2
    echo "Is the gateway up, and are MCP_ADMIN_EMAIL and MCP_ADMIN_PASSWORD still right?" >&2
    exit 1
fi

mkdir -p "$out"

# Named by tool name rather than id, because the id is whatever the database handed out and
# the tool name is the thing a person recognises — and the thing that has to be unique
# anyway.
curl -sf "$api/definitions?size=500" -H "Authorization: Bearer $token" \
    | python3 -c '
import json, sys
page = json.load(sys.stdin)
rows = page.get("content", page) if isinstance(page, dict) else page
for row in rows:
    print(row["id"], row["toolName"])
' | while read -r id name; do
    curl -sf "$api/definitions/$id" -H "Authorization: Bearer $token" \
        | python3 -m json.tool > "$out/$name.json"
    printf '  %-26s %s\n' "$name" "$out/$name.json"
done

echo
echo "Written to $out — ignored by git, and holding sealed keys and host addresses."
