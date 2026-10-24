#!/usr/bin/env bash
# wt's status line plus a clickable link to this worktree's dev server.
# Worktree .env files append their own PORT and PHX_HOST (see .config/wt.toml), so the last value wins.
input=$(cat)
dir=$(git -C "$(jq -r '.workspace.current_dir' <<<"$input")" rev-parse --show-toplevel)
port=$(grep -oE '^export PORT=[0-9]+' "$dir/.env" 2>/dev/null | tail -1 | cut -d= -f2)
host=$(grep -oE '^export PHX_HOST=[^ ]+' "$dir/.env" 2>/dev/null | tail -1 | cut -d= -f2)
url="http://${host:-localhost}:${port:-4000}"
printf '%s  \e]8;;%s\a%s\e]8;;\a\n' "$(wt list statusline --format=claude-code <<<"$input")" "$url" "$url"
