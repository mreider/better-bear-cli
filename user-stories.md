# Bear MCP Server - User Stories

Derived from PRD v0.1.0. Each story follows the format:
**"I should be able to [action], when I am [context], trying to [goal]."**

---

## 1. Setup & Configuration

### 1.1 Installation

- I should be able to **install the MCP server with a single npm command**, when I am **setting up Bear integration for the first time**, trying to **get Bear tools available in Claude Desktop as quickly as possible**.
- I should be able to **add the MCP server to Claude Desktop's config with a simple JSON entry**, when I am **configuring Claude Desktop**, trying to **connect Claude to my Bear notes without learning the MCP protocol**.
- I should be able to **verify the connection works by asking Claude to list my notes**, when I am **finishing setup**, trying to **confirm everything is wired up correctly before relying on it**.

### 1.2 Authentication

- I should be able to **use my existing bcli authentication without re-authenticating**, when I am **setting up the MCP server after already using bcli**, trying to **avoid doing the Apple Sign-In flow again**.
- I should be able to **migrate my auth token from the plain-text file to Keychain**, when I am **improving my security setup**, trying to **stop storing my iCloud token in a readable JSON file**.
- I should be able to **authenticate directly to Keychain on first setup**, when I am **a new user running `bcli auth` for the first time**, trying to **start with secure credential storage from day one**.
- I should be able to **get a clear error message when my auth token has expired**, when I am **using Bear tools in Claude Desktop and my session has gone stale**, trying to **understand why the tool failed and what to do about it** (re-run `bcli auth`).

### 1.3 API Key Management

- I should be able to **store my Anthropic API key securely via the CLI**, when I am **configuring bcli for AI-enhanced features**, trying to **keep my API key in the Keychain instead of an environment variable or config file**.
- I should be able to **confirm my API key is stored without seeing the key itself**, when I am **checking my configuration**, trying to **verify the key is there without exposing it on screen**.
- I should be able to **update or rotate my stored API key**, when I am **managing my Anthropic account**, trying to **replace an old key without leaving traces of it**.

---

## 2. Reading Notes via Claude

### 2.1 Listing & Browsing

- I should be able to **ask Claude to list my recent Bear notes**, when I am **starting a conversation and want to see what I've been working on**, trying to **get an overview of my notes without opening Bear**.
- I should be able to **ask Claude to show notes with a specific tag**, when I am **looking for notes in a particular category** (e.g., "show me my notes tagged 'work'"), trying to **narrow down to relevant notes without scrolling through everything**.
- I should be able to **ask Claude to include archived notes**, when I am **looking for something I archived**, trying to **search my full note history, not just active notes**.

### 2.2 Reading Content

- I should be able to **ask Claude to read a specific note**, when I am **looking at a list of notes and want the full content of one**, trying to **get the complete text of a note conversationally**.
- I should be able to **ask Claude to read just the markdown**, when I am **interested only in the note body, not metadata**, trying to **get clean content without IDs, timestamps, and other fields**.
- I should be able to **ask Claude to read multiple notes in sequence**, when I am **researching a topic that spans several notes**, trying to **gather all relevant context in one conversation**.

### 2.3 Searching

- I should be able to **ask Claude to search my notes for a topic**, when I am **looking for something specific across all my notes**, trying to **find relevant notes without remembering exact titles or tags**.
- I should be able to **get search results with enough context to identify the right note**, when I am **reviewing search results Claude presents**, trying to **pick the right note without having to open each one**.
- I should be able to **search without triggering a full sync**, when I am **searching frequently and don't want to wait**, trying to **get fast results from the local cache**.

### 2.4 Tags

- I should be able to **ask Claude to show my tag hierarchy**, when I am **trying to understand how my notes are organized**, trying to **see the full structure of my tags without opening Bear**.
- I should be able to **ask Claude which tags a specific note has**, when I am **looking at a note's metadata**, trying to **understand how a note is categorized**.

---

## 3. Writing Notes via Claude

### 3.1 Creating Notes

- I should be able to **ask Claude to create a new Bear note**, when I am **in a conversation where we've produced useful content** (meeting notes, research summary, brainstorm), trying to **save the output directly to Bear without copy-pasting**.
- I should be able to **specify tags when creating a note through Claude**, when I am **creating a note that belongs in a specific category**, trying to **have the note organized correctly from the start**.
- I should be able to **ask Claude to create a note from our conversation**, when I am **finishing a productive discussion**, trying to **capture the key points in Bear without manually summarizing**.

### 3.2 Editing Notes

- I should be able to **ask Claude to append text to an existing note**, when I am **adding follow-up content to a note**, trying to **update a note without replacing what's already there**.
- I should be able to **ask Claude to replace the content of a note**, when I am **revising a note based on our conversation**, trying to **update the full body of a note with improved content**.
- I should be able to **ask Claude to edit a specific section of a note**, when I am **refining part of a longer note**, trying to **make targeted changes without touching the rest**.

### 3.3 Deleting Notes

- I should be able to **ask Claude to trash a note**, when I am **cleaning up notes I no longer need**, trying to **remove a note without opening Bear** (safely moves to trash, not permanent delete).
- I should be able to **get confirmation before Claude trashes a note**, when I am **asking Claude to delete something**, trying to **avoid accidentally trashing the wrong note**.

---

## 4. TODO Management via Claude

### 4.1 Reviewing TODOs

- I should be able to **ask Claude to show my open TODOs across all notes**, when I am **starting my day or planning my week**, trying to **see everything I need to do in one place**.
- I should be able to **ask Claude to show TODOs from a specific note**, when I am **focused on one project or topic**, trying to **see the task list for a specific area of work**.
- I should be able to **ask Claude to show TODOs limited to a specific tag**, when I am **focusing on a category of work** (e.g., "show me TODOs tagged 'project-x'"), trying to **filter my task list to what's relevant right now**.

### 4.2 Completing TODOs

- I should be able to **ask Claude to mark a TODO as done**, when I am **reviewing my task list and reporting progress**, trying to **check off completed items without opening Bear**.
- I should be able to **ask Claude to mark multiple TODOs as done**, when I am **batch-updating my task list**, trying to **clear several completed items at once**.
- I should be able to **ask Claude to uncheck a TODO**, when I am **reverting a completed item**, trying to **re-open a task I marked done prematurely**.

---

## 5. Sync & Data Freshness

### 5.1 Syncing

- I should be able to **trust that Claude's view of my notes is reasonably fresh**, when I am **asking about note content**, trying to **get accurate information without manually triggering a sync**.
- I should be able to **ask Claude to force a full sync**, when I am **suspecting stale data or after making changes in Bear directly**, trying to **ensure Claude has the latest version of all my notes**.
- I should be able to **understand when data might be stale**, when I am **reading notes that I recently edited in Bear**, trying to **know whether to trust the content or sync first**.

### 5.2 Export

- I should be able to **ask Claude to export my notes to a directory**, when I am **backing up my notes or preparing them for another tool**, trying to **get markdown files on disk without using Bear's export UI**.
- I should be able to **export with YAML frontmatter**, when I am **exporting for a system that uses frontmatter** (static site generators, Obsidian, etc.), trying to **preserve metadata in the exported files**.
- I should be able to **export only notes matching a specific tag**, when I am **exporting a subset of my notes**, trying to **get just the relevant notes without exporting everything**.

---

## 6. Security & Credentials

### 6.1 Keychain Storage

- I should be able to **have my iCloud auth token stored in the macOS Keychain**, when I am **using bcli**, trying to **keep my credentials encrypted by the OS instead of in a plain-text JSON file**.
- I should be able to **have my Anthropic API key stored in the Keychain**, when I am **configuring AI-enhanced features**, trying to **avoid storing API keys in environment variables or dotfiles that might leak**.
- I should be able to **fall back to file-based auth if Keychain is unavailable**, when I am **running in a CI environment or non-standard setup**, trying to **still use bcli when Keychain access isn't possible**.

### 6.2 Credential Safety

- I should be able to **trust that my credentials never appear in logs or error output**, when I am **debugging an issue with bcli or the MCP server**, trying to **troubleshoot without risking credential exposure**.
- I should be able to **trust that the MCP server doesn't store or cache my note content**, when I am **concerned about data persistence**, trying to **ensure my notes exist only in CloudKit and bcli's cache, nowhere else**.
- I should be able to **trust that no data leaves my machine beyond CloudKit API calls**, when I am **evaluating the security of this setup**, trying to **confirm that the MCP server is purely a local bridge**.

---

## 7. Error Handling & Recovery

### 7.1 Auth Errors & Re-Authentication

- I should be able to **have a browser sign-in window open automatically when my session expires**, when I am **using Bear tools in Claude and my iCloud token has gone stale**, trying to **re-authenticate without leaving my conversation or opening a terminal**.
- I should be able to **sign in via the browser and have Claude's original request just work**, when I am **completing the Apple Sign-In flow that the MCP server triggered**, trying to **get my answer without having to repeat my question to Claude**.
- I should be able to **get a clear timeout error if I don't sign in quickly enough**, when I am **away from my desk or ignoring the sign-in popup**, trying to **understand why the tool call eventually failed** (e.g., "Sign-in timed out after 2 minutes. Try again or run `bcli auth` manually.").
- I should be able to **re-authenticate without restarting the MCP server**, when I am **refreshing my auth token**, trying to **resume my Claude conversation without losing context**.

### 7.2 Network & Sync Errors

- I should be able to **get a clear error when CloudKit is unreachable**, when I am **offline or iCloud is having issues**, trying to **understand whether the problem is on my end or Apple's**.
- I should be able to **still search and read cached notes when offline**, when I am **without internet but have a recent sync**, trying to **access my notes even when CloudKit is unavailable**.

### 7.3 Note Errors

- I should be able to **get a clear error when a note ID doesn't exist**, when I am **referencing a note that was deleted or has a typo in the ID**, trying to **understand why the operation failed**.
- I should be able to **get a meaningful error when an edit conflicts**, when I am **editing a note that was simultaneously changed on another device**, trying to **understand the conflict and decide what to do**.

---

## 8. Workflow Integration

### 8.1 Multi-Step Workflows

- I should be able to **ask Claude to search, read, summarize, and create a new note in one conversation**, when I am **doing research across my notes**, trying to **produce a synthesis note without manually orchestrating each step**.
- I should be able to **ask Claude to review all notes with a tag and suggest which to archive**, when I am **cleaning up my notes**, trying to **organize my note library with AI assistance**.
- I should be able to **ask Claude to find all notes mentioning a topic and compile a summary note**, when I am **preparing for a meeting or review**, trying to **gather context quickly from scattered notes**.

### 8.2 Chaining with Other Tools

- I should be able to **use Bear tools alongside other MCP tools in Claude Desktop**, when I am **using multiple MCP servers** (e.g., file system, calendar, email), trying to **build workflows that span multiple tools and data sources**.
- I should be able to **ask Claude to take information from another source and save it as a Bear note**, when I am **capturing information from the web, email, or another tool**, trying to **funnel information into Bear as my central notes system**.

---

## 9. Performance & Reliability

- I should be able to **get responses from cached operations within a few seconds**, when I am **asking Claude about notes that have been recently synced**, trying to **have a fluid conversation without long waits**.
- I should be able to **trust that the MCP server handles concurrent tool calls safely**, when I am **asking Claude something that triggers multiple Bear operations**, trying to **get correct results even when multiple tools run at once**.
- I should be able to **trust that creating or editing notes won't corrupt my Bear data**, when I am **using Claude to modify notes**, trying to **write to Bear with the same safety guarantees as using Bear directly**.
