# better-bear

MCP server for [Bear](https://bear.app) notes. Read, search, create, edit, tag, and manage your notes from Claude Desktop, Claude Code, or any MCP client. Includes a **context library** for building curated, LLM-optimized knowledge bases from your notes.

Works via CloudKit — no Bear URL scheme, no AppleScript. Your notes stay in sync across all devices.

> **Context Library** — Inspired by [Karpathy's LLM Knowledge Base](https://x.com/karpathy/status/1909382922276999612) pattern: tag Bear notes with `#context`, sync to a local folder, and Claude uses index-first retrieval to navigate your knowledge. No RAG pipeline, no vector database — just curated markdown with a manifest.

## Quick start

### Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "better-bear": {
      "command": "npx",
      "args": ["-y", "better-bear"]
    }
  }
}
```

### Claude Code

```sh
claude mcp add better-bear -- npx -y better-bear
```

### Prerequisites

1. **Node.js 18+**
2. **bcli** — the underlying CLI binary:
   ```sh
   curl -fsSL https://raw.githubusercontent.com/mreider/better-bear-cli/main/install.sh | bash
   ```
3. **Authenticate** with your Apple ID:
   ```sh
   bcli auth
   ```

## Tools

| Tool | Description |
|------|-------------|
| `bear_sync` | Sync notes from iCloud (incremental or full) |
| `bear_list_notes` | List notes with optional tag/archive/trash filters |
| `bear_get_note` | Get full note content, metadata, and front matter |
| `bear_search` | Full-text search with date filters (since/before) |
| `bear_create_note` | Create a note with title, body, tags, front matter |
| `bear_edit_note` | Edit note body, append text, replace sections, manage front matter |
| `bear_trash_note` | Move a note to trash |
| `bear_archive_note` | Archive or unarchive a note |
| `bear_get_tags` | List all tags with note counts |
| `bear_add_tag` | Add a tag to a note |
| `bear_remove_tag` | Remove a tag from a note |
| `bear_rename_tag` | Rename a tag across all notes |
| `bear_delete_tag` | Delete a tag from all notes |
| `bear_find_untagged` | Find notes with no tags |
| `bear_attach_file` | Attach images or files to a note |
| `bear_list_todos` | List notes with incomplete TODOs |
| `bear_get_todos` | Get all TODO items in a note |
| `bear_toggle_todo` | Toggle a TODO item complete/incomplete |
| `bear_note_stats` | Library statistics (counts, words, top tags) |
| `bear_find_duplicates` | Find notes with duplicate titles |
| `bear_health_check` | Diagnose library issues |

### Context library

| Tool | Description |
|------|-------------|
| `bear_context_setup` | Initialize a context library (one-time) |
| `bear_context_sync` | Sync qualifying Bear notes to the library |
| `bear_context_index` | Get the index manifest + freshness metadata |
| `bear_context_fetch` | Load specific files by path |
| `bear_context_search` | Full-text search across all context files |
| `bear_context_add` | Tag a Bear note for inclusion |
| `bear_context_remove` | Untag and remove a note |
| `bear_context_status` | Health stats, token counts, warnings |

## How it works

This MCP server wraps [bcli](https://github.com/mreider/better-bear-cli), a native macOS binary that talks to Bear's CloudKit container. The server communicates with MCP clients via stdio and spawns `bcli` commands for each operation.

Authentication tokens are stored locally in `~/.config/bear-cli/auth.json` and automatically refreshed when expired.

## Links

- [Website](https://better-bear.com)
- [GitHub](https://github.com/mreider/better-bear-cli)
- [Issues](https://github.com/mreider/better-bear-cli/issues)

## License

MIT
