#!/usr/bin/env bash
# Rebuilds graphify-out/graph.json without an LLM (see tools/graphify_rebuild.py).
# Runs at session start from the cloud environment's setup script; run it by hand
# after code changes in a session. Needs the graphify CLI (uv tool install graphifyy).
#
#   tools/graphify_rebuild.sh [--html | --save-names]

set -euo pipefail
cd "$(dirname "$0")/.."

graphify_bin=$(command -v graphify || true)
if [ -z "$graphify_bin" ]; then
	echo "[graphify rebuild] graphify is not installed (uv tool install graphifyy); skipping" >&2
	exit 1
fi
# graphify's own interpreter, which has the graphify package (uv tool and pipx installs).
python_bin=$(head -1 "$graphify_bin" | sed 's/^#!//')
case "$python_bin" in
*[!a-zA-Z0-9/_.@-]*) python_bin=python3 ;;
esac

exec "$python_bin" tools/graphify_rebuild.py "$@"
