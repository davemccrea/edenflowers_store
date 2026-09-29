#!/bin/bash
# Installs the Typst CLI used to render receipt PDFs into ~/.local/bin.
# Must match TYPST_VERSION in Dockerfile and .github/workflows/ci.yml. Bump all three together.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

TYPST_VERSION=0.14.2
INSTALL_DIR="$HOME/.local/bin"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  target=x86_64-unknown-linux-musl ;;
  Linux-aarch64) target=aarch64-unknown-linux-musl ;;
  Darwin-x86_64) target=x86_64-apple-darwin ;;
  Darwin-arm64)  target=aarch64-apple-darwin ;;
  *) fail "No Typst release for $(uname -s) $(uname -m)" ;;
esac

section "Installing Typst $TYPST_VERSION ($target)"
mkdir -p "$INSTALL_DIR"
# `tar` can exit 0 with nothing extracted if the archive layout changes, hence the version check below.
curl --fail-with-body -sSL "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-${target}.tar.xz" \
  | tar -xJ --strip-components=1 -C "$INSTALL_DIR" "typst-${target}/typst"

installed=$("$INSTALL_DIR/typst" --version)
ok "$installed → $INSTALL_DIR/typst"

if [[ "$(command -v typst)" != "$INSTALL_DIR/typst" ]]; then
  fail "$INSTALL_DIR is not first on your PATH for typst. Add it to PATH"
fi
