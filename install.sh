#!/usr/bin/env bash
set -euo pipefail

REPO="mreider/better-bear-cli"
INSTALL_DIR="${HOME}/.local/bin"
BINARY="bcli"

echo "Installing better-bear-cli..."

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download and extract
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -sL "https://github.com/${REPO}/releases/latest/download/bcli-macos-universal.tar.gz" -o "$TMPDIR/bcli.tar.gz"
tar xzf "$TMPDIR/bcli.tar.gz" -C "$TMPDIR"
mv "$TMPDIR/bcli" "$INSTALL_DIR/$BINARY"
chmod +x "$INSTALL_DIR/$BINARY"

echo "Installed to $INSTALL_DIR/$BINARY"

# Check if install dir is in PATH
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
  SHELL_NAME=$(basename "$SHELL")
  case "$SHELL_NAME" in
    zsh)  RC="$HOME/.zshrc" ;;
    bash) RC="$HOME/.bashrc" ;;
    *)    RC="" ;;
  esac
  echo ""
  echo "NOTE: $INSTALL_DIR is not in your PATH."
  if [ -n "$RC" ]; then
    echo "Add it by running:"
    echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> $RC && source $RC"
  else
    echo "Add $INSTALL_DIR to your PATH."
  fi
fi

echo ""
echo "Run 'bcli auth' to authenticate with iCloud."
