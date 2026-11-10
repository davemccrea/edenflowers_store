#!/usr/bin/env bash
set -euo pipefail

port=${1:?Usage: start-worktree-server.sh PORT}
mkdir -p tmp
nohup wt step tether -- just dev > tmp/dev.log 2>&1 < /dev/null &

if ! curl --silent --show-error --fail --output /dev/null \
  --connect-timeout 1 --max-time 3 \
  --retry 60 --retry-delay 1 --retry-max-time 60 --retry-all-errors \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json, text/event-stream' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"worktrunk","version":"1"}}}' \
  "http://localhost:$port/tidewave/mcp" 2> tmp/dev-ready.log; then
  echo "Worktree server did not become ready. See tmp/dev.log and tmp/dev-ready.log." >&2
  exit 1
fi
