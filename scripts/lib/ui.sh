#!/bin/bash
# Shared UI helpers for scripts/. Source this file, then use section/ok/fail.

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; CYAN=$'\033[36m'
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; CYAN=""
fi

section() { printf '\n%s▶ %s%s\n' "$BOLD$CYAN" "$1" "$RESET"; }
ok()      { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
fail()    { printf '  %s✗ %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }
