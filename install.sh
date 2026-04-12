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

# --- Optional MCP server setup ---

setup_mcp() {
  echo ""
  echo "Setting up MCP server for Claude..."

  # Check for Node.js
  if ! command -v node &>/dev/null; then
    echo "Node.js is required for the MCP server. Install it from https://nodejs.org"
    return 1
  fi

  NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
  if [ "$NODE_VERSION" -lt 18 ]; then
    echo "Node.js 18+ is required (found v$(node -v)). Update from https://nodejs.org"
    return 1
  fi

  # Determine Claude config path
  CLAUDE_DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  CLAUDE_CODE_CONFIG="$HOME/.claude.json"

  configure_claude_desktop() {
    local config="$1"
    local dir
    dir=$(dirname "$config")
    mkdir -p "$dir"

    if [ ! -f "$config" ]; then
      cat > "$config" << 'JSONEOF'
{
  "mcpServers": {
    "better-bear": {
      "command": "npx",
      "args": ["-y", "better-bear"]
    }
  }
}
JSONEOF
      echo "Created $config with better-bear MCP server."
    elif grep -q '"better-bear"' "$config" 2>/dev/null; then
      echo "better-bear MCP server already configured in $config"
    else
      # Use python3 to merge into existing config (available on macOS)
      python3 -c "
import json, sys
with open('$config') as f:
    cfg = json.load(f)
cfg.setdefault('mcpServers', {})['better-bear'] = {
    'command': 'npx',
    'args': ['-y', 'better-bear']
}
with open('$config', 'w') as f:
    json.dump(cfg, f, indent=2)
"
      echo "Added better-bear MCP server to $config"
    fi
  }

  # Set up for Claude Desktop if installed
  if [ -d "/Applications/Claude.app" ] || [ -d "$HOME/Applications/Claude.app" ]; then
    configure_claude_desktop "$CLAUDE_DESKTOP_CONFIG"
    echo "Restart Claude Desktop to activate the MCP server."
  else
    echo "Claude Desktop not found. To configure manually, add to claude_desktop_config.json:"
    echo '  "better-bear": { "command": "npx", "args": ["-y", "better-bear"] }'
  fi

  echo ""
  echo "For Claude Code, run:"
  echo "  claude mcp add better-bear -- npx -y better-bear"
}

# Check for --mcp flag or prompt
if [[ "${1:-}" == "--mcp" ]]; then
  setup_mcp
elif [[ -t 0 ]]; then
  # Interactive terminal — ask
  echo ""
  printf "Set up MCP server for Claude? (y/N) "
  read -r REPLY
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    setup_mcp
  fi
fi
