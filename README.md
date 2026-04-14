# better bear

[![better-bear MCP server](https://glama.ai/mcp/servers/KuvopLLC/better-bear/badges/card.svg)](https://glama.ai/mcp/servers/KuvopLLC/better-bear)

[![Build](https://github.com/KuvopLLC/better-bear/actions/workflows/build-on-merge.yml/badge.svg)](https://github.com/KuvopLLC/better-bear/actions/workflows/build-on-merge.yml)
[![Release](https://img.shields.io/github/v/release/KuvopLLC/better-bear)](https://github.com/KuvopLLC/better-bear/releases/latest)
[![npm](https://img.shields.io/npm/v/better-bear)](https://www.npmjs.com/package/better-bear)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/KuvopLLC/better-bear/blob/main/LICENSE)
[![better-bear MCP server](https://glama.ai/mcp/servers/KuvopLLC/better-bear/badges/score.svg)](https://glama.ai/mcp/servers/KuvopLLC/better-bear)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-orange?logo=buy-me-a-coffee&logoColor=white)](https://buymeacoffee.com/mreider)

MCP server and CLI for [Bear](https://bear.app) notes via CloudKit. Includes a **context library** — a curated, synced folder of notes optimized for LLM consumption, inspired by [Karpathy's LLM Knowledge Base](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern.

**Full docs: [better-bear.com](https://better-bear.com)**

## Install

Install the CLI, then connect to Claude:

```
curl -sL https://raw.githubusercontent.com/KuvopLLC/better-bear/main/install.sh | bash
bcli auth
bcli mcp install
```

This installs the `bcli` binary, authenticates with iCloud, and sets up the MCP server for both Claude Desktop (via `.mcpb` bundle) and Claude Code.

### Other install methods

| Method | Command |
|--------|---------|
| Claude Desktop only | `bcli mcp install --desktop-only` |
| Claude Code only | `bcli mcp install --code-only` |
| Claude Code (direct) | `claude mcp add better-bear -- npx -y better-bear` |
| Config file | `bcli mcp install --json` |
| .mcpb bundle | Download from [latest release](https://github.com/KuvopLLC/better-bear/releases/latest) and double-click |

### Manage

```
bcli mcp status      # check what's configured
bcli mcp uninstall   # remove from Claude Desktop and Claude Code
bcli mcp reinstall   # clean uninstall + install
bcli upgrade         # upgrade bcli binary
```

## CLI

All commands also work standalone from the terminal:

```
bcli ls                          # list notes
bcli search "query"              # full-text search
bcli create "Title" -b "Body"    # create a note
bcli edit <id> --append "text"   # append to a note
bcli tags                        # list all tags
bcli attach <id> photo.jpg       # attach a file
bcli stats                       # library statistics
bcli health                      # health check
```

See [better-bear.com](https://better-bear.com) for the full command reference.

## Context Library

Turn a subset of your Bear notes into a synced, curated context folder that Claude can navigate using index-first retrieval. Tag notes with `#context` in Bear, sync, and Claude reads a compact index to find relevant files — loading only what it needs, not everything.

```
bcli context init                          # one-time setup
bcli context sync                          # pull qualifying notes
bcli context add <id> --subtag research    # tag a note for inclusion
bcli context status                        # health check
```

Or tell Claude: *"Set up a context library"* — and it handles everything via MCP tools.

The architecture follows Karpathy's three-folder pattern: `bear/` (synced from CloudKit), `external/` (PDFs, exports, shared docs), and `inbox/` (drop zone for triage). An `index.md` manifest maps everything. See [better-bear.com](https://better-bear.com#context-library) for full documentation.

## MCP Tools

34 tools covering notes, tags, TODOs, attachments, search, front matter, stats, health checks, and the context library. See the [MCP server README](mcp-server/README.md) for the full list.

## Contributors

<a href="https://github.com/mreider"><img src="https://avatars.githubusercontent.com/u/118036?v=4" width="50" height="50" style="border-radius:50%" alt="mreider"></a>
<a href="https://github.com/program247365"><img src="https://avatars.githubusercontent.com/u/13910?v=4" width="50" height="50" style="border-radius:50%" alt="program247365"></a>
<a href="https://github.com/asabirov"><img src="https://avatars.githubusercontent.com/u/733858?v=4" width="50" height="50" style="border-radius:50%" alt="asabirov"></a>
<a href="https://github.com/darronz"><img src="https://avatars.githubusercontent.com/u/136805?v=4" width="50" height="50" style="border-radius:50%" alt="darronz"></a>
