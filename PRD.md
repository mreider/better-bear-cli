# Bear MCP Server - Product Requirements Document

**Version:** 0.1.0
**Last updated:** 2026-04-11
**Tagline:** Your Bear notes, available to Claude as tools.

---

## 1. Problem

Bear is a great note-taking app, but it has no way to talk to AI assistants. Users who want Claude to read, search, create, or organize their Bear notes have to copy-paste manually between Claude and Bear. This is slow, lossy, and defeats the purpose of having an AI assistant.

Today, the workarounds are:

- **Copy-paste manually.** Open Bear, find the note, copy text, paste into Claude, wait for a response, copy it back. Tedious for one note, unusable for workflows that span many notes.
- **Use bcli in the terminal.** better-bear-cli already provides full programmatic access to Bear via CloudKit, but there's no bridge between bcli and AI assistants. Users have to manually run commands and feed output to Claude.
- **Export everything to files.** Some users export all Bear notes to a directory so Claude Code can read them. This is a one-way snapshot -- stale immediately, no write-back, and doesn't work with Claude Desktop at all.

The underlying problem: Bear notes are locked behind a GUI. bcli unlocked them for the terminal. Now they need to be unlocked for AI assistants.

---

## 2. Solution

Build an MCP (Model Context Protocol) server that exposes Bear note operations as tools Claude Desktop can call directly. The server wraps bcli's existing capabilities -- listing, reading, searching, creating, editing, and organizing notes -- and makes them available through the standard MCP interface.

**The core idea: Claude asks Bear directly. No copy-paste. No export. No manual commands.**

**Example:** A user asks Claude Desktop "what are my open TODOs across all my Bear notes?" Claude calls the `bear_list_todos` tool, gets structured results, and presents them conversationally -- with links back to specific notes if the user wants to drill in.

### What makes this different from just using bcli

- **Conversational.** Users interact through natural language, not CLI flags. Claude handles the translation.
- **Contextual.** Claude can chain multiple Bear operations together -- search for notes, read them, summarize patterns, create new notes with findings -- all in one conversation.
- **Secure.** Credentials are stored in the macOS Keychain, not plain text files. The Anthropic API key (for optional AI-enhanced CLI features) is stored the same way.
- **Zero-config for users.** Once the MCP server is pointed at in Claude Desktop's config, all Bear tools are auto-discovered. No manual tool registration.

---

## 3. Users

### Primary: People who use both Bear and Claude Desktop

Anyone who keeps notes in Bear and uses Claude Desktop as their AI assistant. They want Claude to be able to work with their notes directly -- reading context, finding information, drafting content, managing TODOs -- without leaving the conversation.

### Secondary: Developers and power users

Technical users who want to build workflows on top of Bear using AI. They may chain Bear MCP tools with other MCP servers, build automations, or use the enhanced CLI features for scripting.

---

## 4. Core Concepts

### MCP Server

A lightweight process that Claude Desktop launches and communicates with over stdio. It advertises Bear operations as tools with typed parameters and returns structured results. The server is the bridge between Claude's natural language understanding and bcli's CloudKit API access.

### Tools

Individual Bear operations exposed to Claude Desktop. Each tool has a name, description, input schema, and returns structured output. Tools map closely to bcli commands but are designed for AI consumption -- richer descriptions, structured JSON output, sensible defaults.

### Credential Store

All sensitive credentials -- the iCloud auth token and optionally an Anthropic API key -- are stored in the macOS Keychain rather than plain text files. This provides OS-level encryption, access control, and integration with the system's security infrastructure.

### Local Cache

bcli's existing sync engine and local cache (`~/.config/bear-cli/cache.json`) provide fast access to note content without hitting CloudKit on every request. The MCP server leverages this cache, triggering syncs as needed.

---

## 5. Architecture

### System Overview

```
Claude Desktop
    |
    | stdio (MCP protocol)
    |
MCP Server (Node.js / TypeScript)
    |
    | child_process.exec
    |
bcli (Swift binary)
    |
    | HTTPS
    |
CloudKit REST API (api.apple-cloudkit.com)
    |
    | iCloud Sync
    |
Bear App (all devices)
```

### Why TypeScript wrapping bcli (not a pure Swift MCP server)

- The MCP SDK (`@modelcontextprotocol/sdk`) is mature and well-maintained in TypeScript.
- bcli already handles all CloudKit complexity -- auth, sync, vector clocks, conflict resolution, encryption metadata. Reimplementing this would be error-prone and redundant.
- The MCP server is a thin translation layer: parse tool calls, shell out to bcli with `--json`, return structured results. Minimal logic lives here.
- Future AI-enhanced features (semantic search, smart tagging) can use the Anthropic TypeScript SDK directly.

### Why not call CloudKit directly from TypeScript

bcli contains hard-won implementation details: vector clock binary plist encoding, `textADP` vs `text` asset handling, percent-encoding `+` as `%2B`, encrypted field metadata, atomic cache writes, and more. Duplicating this in TypeScript would be a significant effort with a high risk of subtle bugs. Wrapping bcli treats it as a reliable black box.

---

## 6. User Journeys

### 6.1 First-Time Setup

**Goal:** Get Claude Desktop talking to Bear notes.

1. User installs bcli (if not already installed).
2. User runs `bcli auth` to authenticate with iCloud (existing flow).
3. User installs the MCP server package (npm install or binary).
4. User adds the MCP server to Claude Desktop's configuration file (`claude_desktop_config.json`).
5. User restarts Claude Desktop. Bear tools appear in the tool list.
6. User asks Claude "list my recent Bear notes" to verify everything works.

### 6.2 Reading and Searching Notes

**Goal:** Find and read Bear notes through conversation.

1. User asks Claude a question that requires Bear note content (e.g., "what did I write about the Q3 roadmap?").
2. Claude calls `bear_search` with the relevant query.
3. MCP server runs `bcli search "Q3 roadmap" --json`, returns results.
4. Claude reads the search results, may call `bear_get_note` for full content on the most relevant hit.
5. Claude synthesizes the information and responds conversationally.

### 6.3 Creating and Editing Notes

**Goal:** Use Claude to draft, create, or modify Bear notes.

1. User asks Claude to create a note (e.g., "create a Bear note with meeting minutes from what we just discussed").
2. Claude drafts the content, calls `bear_create_note` with title, body, and tags.
3. MCP server runs `bcli create "Meeting Minutes - Apr 11" -b "..." -t "meetings,work" --json`.
4. Note appears in Bear across all devices via iCloud sync.

### 6.4 Managing TODOs

**Goal:** Review and manage TODOs across Bear notes.

1. User asks "what's on my TODO list?"
2. Claude calls `bear_list_todos` to get all notes with incomplete items.
3. Claude presents the list, organized by note/tag.
4. User says "mark the first three as done."
5. Claude calls `bear_toggle_todo` for each item.

### 6.5 Transparent Re-Authentication

**Goal:** Session expires mid-conversation; user re-authenticates without leaving Claude Desktop.

1. User asks Claude something that triggers a Bear tool call.
2. bcli returns an auth expiry error (HTTP 401/421).
3. MCP server detects the auth error and automatically launches `bcli auth`, which opens the user's browser to the Apple Sign-In page.
4. MCP server watches for the auth token to be written (polling the Keychain or auth file).
5. User signs in via the browser. Token is captured and saved.
6. MCP server detects the new token, retries the original bcli command.
7. Result is returned to Claude as if nothing happened.
8. If the user doesn't sign in within 2 minutes, the server returns a clear error: "Sign-in timed out. Run `bcli auth` manually or try again."

From the user's perspective: a browser window appears, they sign in, and Claude just has the answer. No "try again" step needed.

### 6.6 Credential Migration (Optional)

**Goal:** Move from plain-text auth to Keychain storage.

1. User runs `bcli auth --migrate-to-keychain`.
2. bcli reads the existing token from `~/.config/bear-cli/auth.json`.
3. Token is stored in macOS Keychain under a service identifier.
4. Plain-text file is securely deleted.
5. All subsequent bcli operations read from Keychain.

---

## 7. Features

### 7.1 MCP Server

The core deliverable: a stdio-based MCP server that exposes Bear operations as tools.

**Requirements:**
- Implement the MCP protocol using `@modelcontextprotocol/sdk`.
- Expose all major bcli operations as individual tools (see 7.2).
- All tool outputs are structured JSON -- no raw text parsing by Claude.
- Handle bcli errors gracefully: network failures, note-not-found, and sync conflicts should return clear error messages, not stack traces.
- **Transparent re-authentication:** When bcli returns an auth expiry error, the MCP server automatically launches `bcli auth` (which opens the browser for Apple Sign-In), waits up to 2 minutes for the user to complete sign-in, then retries the original operation. If sign-in times out, return a clear error message. The user should never need to manually re-run a tool call after re-authenticating.
- Auto-sync before read operations when the cache is stale (respect bcli's 5-minute TTL).
- Support Claude Desktop's MCP server lifecycle (startup, tool discovery, execution, shutdown).

### 7.2 MCP Tool Definitions

Each tool maps to a bcli command. All tools return JSON.

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `bear_list_notes` | List notes with optional filtering | `tag`, `include_archived`, `limit` |
| `bear_get_note` | Get a single note's full content and metadata | `id`, `raw` (markdown only) |
| `bear_search` | Full-text search across title, tags, and body | `query`, `limit` |
| `bear_get_tags` | Get the full tag hierarchy | _(none)_ |
| `bear_create_note` | Create a new note | `title`, `body`, `tags` |
| `bear_edit_note` | Edit an existing note | `id`, `append_text`, `body` (replace) |
| `bear_trash_note` | Move a note to trash | `id` |
| `bear_sync` | Trigger a sync with CloudKit | `full` (force full re-sync) |
| `bear_list_todos` | List notes with incomplete TODO items | `limit` |
| `bear_toggle_todo` | Toggle a specific TODO item in a note | `id`, `item_index` |
| `bear_export` | Export notes as markdown | `path`, `tag`, `frontmatter` |

Tool descriptions should be written for Claude's consumption -- clear enough that Claude can select the right tool and provide correct parameters from a natural language request.

### 7.3 Keychain Credential Storage

Move sensitive credentials from plain-text files to macOS Keychain.

**Requirements:**
- Store the iCloud auth token in Keychain under a dedicated service name (e.g., `com.better-bear-cli.auth`).
- Optionally store an Anthropic API key in Keychain (e.g., `com.better-bear-cli.anthropic`).
- Provide migration from the existing `~/.config/bear-cli/auth.json` file-based storage.
- Use the macOS `security` CLI for Keychain operations (no native module dependencies).
- Fall back to file-based storage if Keychain access fails (e.g., in CI environments), with a warning.
- Auth token validation and refresh flow remain unchanged -- only the storage backend changes.

### 7.4 CLI Enhancements

Minimal additions to bcli itself to support the MCP workflow.

**Requirements:**
- `bcli auth --migrate-to-keychain` -- migrate existing file-based auth to Keychain.
- `bcli auth --keychain` -- authenticate and store directly in Keychain.
- `bcli config set anthropic-key` -- securely prompt for and store an Anthropic API key in Keychain.
- `bcli config get anthropic-key` -- confirm whether a key is stored (never print the key itself).
- All existing commands continue to work unchanged. Keychain is checked first, file fallback second.

---

## 8. Security Requirements

### Credential Storage
- iCloud auth tokens and API keys are stored in the macOS Keychain, encrypted at rest by the OS.
- Plain-text auth file (`~/.config/bear-cli/auth.json`) is only used as a fallback and can be migrated away.
- The Anthropic API key is never logged, printed, or included in error messages.
- Keychain items are scoped to the current user and require user-level authentication to access.

### MCP Transport Security
- The MCP server communicates with Claude Desktop over stdio -- no network sockets, no HTTP, no attack surface.
- The server runs as the local user with the same permissions as bcli.
- No data leaves the machine except the existing CloudKit API calls to `api.apple-cloudkit.com`.

### Data Handling
- Note content passes through the MCP server but is not stored, logged, or cached by the server itself. bcli's own cache is the only persistent store.
- The MCP server does not phone home, collect telemetry, or communicate with any service other than bcli.

---

## 9. Platform Requirements

- **macOS only.** Bear is a macOS/iOS app. bcli requires macOS 13+. The Keychain integration is macOS-specific. This is intentional -- the scope is deliberately narrow.
- **Node.js 18+** for the MCP server runtime.
- **bcli must be installed and authenticated** before the MCP server can function.
- **Claude Desktop** as the primary MCP client (other MCP-compatible clients should work but are not explicitly targeted).

---

## 10. Success Metrics

- **Setup time:** A user with bcli already installed and authenticated can get Bear tools working in Claude Desktop in under 5 minutes.
- **Tool reliability:** Bear tool calls succeed on the first try >95% of the time (excluding auth expiry).
- **Coverage:** All 11 bcli commands are accessible through MCP tools.
- **Latency:** Tool responses return within 3 seconds for cached operations, within 10 seconds for operations requiring a sync.

---

## 11. Future Considerations

These are explicitly **not** in scope for v1 but are worth noting for future direction.

### AI-Enhanced CLI Features (Phase 2)
Using a stored Anthropic API key to add intelligence to the CLI itself:
- **Semantic search:** Index notes with embeddings for meaning-based search, not just text matching.
- **Smart tagging:** Suggest tags for notes based on content analysis.
- **Note summarization:** Generate summaries of long notes or groups of notes.
- **Related notes:** Surface connections between notes that share concepts but not keywords.

### Multi-User / Team Support
If Bear ever adds shared notebooks or team features, the MCP server could support multi-user access patterns.

### Other MCP Clients
While Claude Desktop is the target, the MCP protocol is an open standard. VS Code extensions, other AI assistants, or custom tools could connect to the same server.

---

## 12. Open Questions

- Should the MCP server support streaming responses for large note exports, or is batch response sufficient?
- ~~What's the right behavior when `bcli auth` has expired mid-conversation?~~ **Resolved:** Auto-launch `bcli auth`, wait up to 2 minutes, retry the operation. See 6.5 and 7.1.
- Should there be a `bear_batch` tool that accepts multiple operations in one call for efficiency?
- Is there value in a `bear_stats` tool that returns note counts, tag distribution, etc. for "dashboard" style queries?
- Should the MCP server support resource URIs (e.g., `bear://note/{id}`) in addition to tools, for direct note content access?
