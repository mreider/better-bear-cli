# bcli (better-bear-cli) -- Full Specification

Version: 0.3.3
Last updated: 2026-03-29

This document is a complete specification for bcli, a macOS command-line tool for managing Bear notes through iCloud's CloudKit REST API. It contains everything needed to rebuild the application from scratch.

---

## Table of Contents

1. [Overview](#1-overview)
2. [CloudKit API and Bear's Schema](#2-cloudkit-api-and-bears-schema)
3. [Authentication](#3-authentication)
4. [Data Models](#4-data-models)
5. [Local Cache and Sync Engine](#5-local-cache-and-sync-engine)
6. [CLI Commands](#6-cli-commands)
7. [Note ID Resolution](#7-note-id-resolution)
8. [Project Structure](#8-project-structure)
9. [CI/CD and Release](#9-cicd-and-release)
10. [Testing](#10-testing)

---

## 1. Overview

### What it is

bcli is a command-line interface for [Bear](https://bear.app) notes. It talks directly to iCloud's CloudKit REST API -- the same API that Bear's web client (web.bear.app) uses. It does not touch Bear's local SQLite database, and it does not use Bear's x-callback-url scheme.

### Why it exists

Bear's x-callback-url API is awkward for programmatic use. Accessing Bear's SQLite database directly risks database corruption. As markdown notes become central to LLM workflows, Bear needs a real programmatic interface. This CLI fills that gap.

### How it works (high level)

Bear Web is a CloudKit JS client that talks to `api.apple-cloudkit.com`. There is no Shiny Frog backend. Notes live in your iCloud private database under the container `iCloud.net.shinyfrog.bear` in a custom zone called `Notes`. This CLI makes the same REST API calls Bear Web makes.

### Safety guarantee

The CLI is safe to use while Bear is open on any device. It does not touch Bear's local SQLite database. Running the CLI is no different from having Bear open on two devices at once. CloudKit handles concurrency with optimistic locking via `recordChangeTag`.

### Platform requirements

- macOS 13 or later
- Swift 5.9 or later
- Single external dependency: [swift-argument-parser](https://github.com/apple/swift-argument-parser) 1.3+

---

## 2. CloudKit API and Bear's Schema

This section documents Bear's CloudKit structure. All of this was reverse-engineered from Bear Web's network traffic.

### Base URL

All API calls go to:

```
https://api.apple-cloudkit.com/database/1/iCloud.net.shinyfrog.bear/production/private
```

The URL breaks down as:
- `/database/1` -- CloudKit Web Services API version 1
- `/iCloud.net.shinyfrog.bear` -- Bear's iCloud container identifier
- `/production` -- environment (not development)
- `/private` -- user's private database (not public or shared)

### Authentication parameters

Every request includes two query parameters:
- `ckWebAuthToken` -- the user's iCloud session token (obtained through Apple Sign-In)
- `ckAPIToken` -- a fixed application token: `ce59f955ec47e744f720aa1d2816a4e985e472d8b859b6c7a47b81fd36646307`

Important: when encoding these query parameters, the `+` character must be percent-encoded as `%2B`. Apple's servers decode `+` as a space, which corrupts tokens. Standard URL encoding libraries (including Swift's `URLQueryItem`) do not encode `+` by default.

### Zone

Bear stores all data in a single custom zone named `Notes` within the user's private database.

### Record types

Bear uses three record types:

#### SFNote (notes)

The main note record. Fields:

| Field | Type | Description |
|-------|------|-------------|
| `uniqueIdentifier` | STRING | Bear's human-friendly note ID (a UUID string) |
| `title` | STRING | Note title (plain text, not encrypted) |
| `text` | ASSET | Note content as a downloadable asset (used for large notes) |
| `textADP` | STRING (encrypted) | Note content inline (used for smaller notes). Takes priority over `text`. |
| `subtitle` | STRING | Subtitle (plain text, can be null) |
| `subtitleADP` | STRING (encrypted) | Subtitle (encrypted version) |
| `tags` | STRING_LIST | List of tag record IDs (UUIDs, not tag titles) |
| `tagsStrings` | STRING_LIST | List of tag titles as plain strings |
| `pinned` | INT64 | 1 if pinned, 0 otherwise |
| `pinnedDate` | TIMESTAMP | When the note was pinned (null if not pinned) |
| `pinnedInTagsStrings` | STRING_LIST | Tags in which this note is pinned (null if none) |
| `archived` | INT64 | 1 if archived, 0 otherwise |
| `archivedDate` | TIMESTAMP | When the note was archived (null if not) |
| `trashed` | INT64 | 1 if trashed, 0 otherwise |
| `trashedDate` | TIMESTAMP | When the note was trashed (null if not) |
| `locked` | INT64 | 1 if locked, 0 otherwise |
| `lockedDate` | TIMESTAMP | When the note was locked (null if not) |
| `encrypted` | INT64 | 1 if encrypted, 0 otherwise |
| `encryptedData` | STRING | Encrypted content (null if not encrypted) |
| `todoCompleted` | INT64 | Count of completed TODO items (`- [x]`) |
| `todoIncompleted` | INT64 | Count of incomplete TODO items (`- [ ]`) |
| `sf_creationDate` | TIMESTAMP | Note creation time (milliseconds since epoch) |
| `sf_modificationDate` | TIMESTAMP | Note modification time (milliseconds since epoch) |
| `vectorClock` | BYTES | Binary plist vector clock for conflict resolution |
| `lastEditingDevice` | STRING | Name of the device that last edited the note |
| `version` | INT64 | Record schema version (currently 3) |
| `hasImages` | INT64 | 1 if the note contains images, 0 otherwise |
| `hasFiles` | INT64 | 1 if the note contains file attachments, 0 otherwise |
| `hasSourceCode` | INT64 | 1 if the note contains source code blocks, 0 otherwise |
| `files` | STRING_LIST | List of file attachment identifiers |
| `linkedBy` | STRING_LIST | IDs of notes that link to this note |
| `linkingTo` | STRING_LIST | IDs of notes this note links to |
| `conflictUniqueIdentifier` | STRING | Used for conflict resolution (null normally) |
| `conflictUniqueIdentifierDate` | TIMESTAMP | Timestamp for conflict resolution (null normally) |

Notes on field behavior:
- `text` vs `textADP`: Bear stores note content in one of two ways. Small notes use `textADP` (an inline encrypted string). Larger notes use `text` (a CloudKit asset with a `downloadURL`). When reading, always try `textADP` first; if absent, download the asset from the `text` field's `downloadURL`. When writing, always write to `textADP`.
- **Encrypted fields:** When writing to `textADP` and `subtitleADP`, the field metadata must include `"isEncrypted": true` alongside the `value` and `type`. Example: `{"value": "...", "type": "STRING", "isEncrypted": true}`. This flag is required for CloudKit to handle these fields correctly.
- Timestamps are in milliseconds since Unix epoch (not seconds).
- Boolean fields use INT64 where 1 = true, 0 = false.

#### SFNoteTag (tags)

Tag records. Fields:

| Field | Type | Description |
|-------|------|-------------|
| `uniqueIdentifier` | STRING | Tag's unique ID (UUID) |
| `title` | STRING | Tag name (e.g., "work" or "work/projects") |
| `notesCount` | INT64 | Number of notes with this tag |
| `pinned` | INT64 | 1 if pinned, 0 otherwise |
| `pinnedDate` | TIMESTAMP | When the tag was pinned |
| `pinnedNotes` | STRING_LIST | IDs of notes pinned within this tag |
| `pinnedNotesDate` | TIMESTAMP | Date of the pinned notes list |
| `isRoot` | INT64 | 1 if this is a top-level tag (no `/` in the name), 0 if nested |
| `sorting` | INT64 | Sort order preference |
| `sortingDate` | TIMESTAMP | When sorting was last changed |
| `tagcon` | STRING | Tag configuration (null normally) |
| `tagconDate` | TIMESTAMP | Date of tag configuration change |
| `version` | INT64 | Record schema version (currently 3) |
| `sf_modificationDate` | TIMESTAMP | Last modification time |

Tags are hierarchical. A tag with title "work/projects" is a child of "work". The hierarchy is encoded in the title using `/` as a separator. The `isRoot` field is 1 only if the tag title contains no `/`.

#### SFNoteBackLink (wiki links)

Records representing links between notes. The CLI does not currently create or modify these records, but they exist in the schema.

### REST endpoints

The CLI uses these CloudKit REST endpoints:

#### `POST /records/query`

Queries records by type with optional filters and sorting.

Request body:
```json
{
  "zoneID": {"zoneName": "Notes"},
  "query": {
    "recordType": "SFNote",
    "filterBy": [
      {
        "fieldName": "trashed",
        "comparator": "EQUALS",
        "fieldValue": {"value": 0, "type": "INT64"}
      }
    ],
    "sortBy": [
      {"fieldName": "pinned", "ascending": false},
      {"fieldName": "sf_modificationDate", "ascending": false}
    ]
  },
  "resultsLimit": 50,
  "desiredKeys": ["title", "uniqueIdentifier", ...]
}
```

Response includes a `records` array and an optional `continuationMarker` for pagination.

Notes sort order: pinned notes first (descending), then by modification date (newest first).

Tags sort order: alphabetical by title (ascending).

#### `POST /records/lookup`

Fetches specific records by their `recordName`.

Request body:
```json
{
  "records": [{"recordName": "some-uuid"}],
  "zoneID": {"zoneName": "Notes"},
  "desiredKeys": [...]
}
```

Records returned without any fields (empty `fields` dictionary) indicate the record was not found. The CLI filters these out.

#### `POST /records/modify`

Creates or updates records. Used for creating notes, creating tags, updating note text, and trashing notes.

Request body:
```json
{
  "operations": [
    {
      "operationType": "create",
      "record": {
        "recordName": "new-uuid",
        "recordType": "SFNote",
        "fields": {...},
        "pluginFields": {},
        "recordChangeTag": null,
        "created": null,
        "modified": null,
        "deleted": false
      },
      "recordType": "SFNote"
    }
  ],
  "zoneID": {"zoneName": "Notes"}
}
```

For updates, set `operationType` to `"update"` and include the existing `recordChangeTag` for optimistic locking. The `created` and `modified` timestamps should be preserved from the original record, with `modified.timestamp` set to the current time.

Multiple operations can be submitted in a single request (e.g., creating a note and its tags together).

#### `POST /zones/list`

Lists all zones in the private database. Used to validate that the auth token works and to get the current sync token for the Notes zone.

Request body: `{}`

Response includes a `zones` array, each with `zoneID` and `syncToken`.

#### `POST /changes/zone`

Fetches records that have changed since a given sync token. Used for incremental sync.

Request body:
```json
{
  "zones": [
    {
      "zoneID": {"zoneName": "Notes"},
      "syncToken": "previous-token-string",
      "resultsLimit": 200
    }
  ]
}
```

Response includes updated/created records, deleted records (with `deleted: true`), a new `syncToken`, and a `moreComing` boolean indicating if there are more changes to fetch.

### Pagination

Query results use a `continuationMarker` string. To fetch the next page, include the marker in the next request body. When `continuationMarker` is null, all results have been fetched. The CLI uses a page size of 200 for full-sync queries.

### Optimistic locking

Every record has a `recordChangeTag` (an opaque string). When updating a record, the current `recordChangeTag` must be included. If another device modified the record since it was fetched, the server rejects the update. The CLI does not retry on conflict -- it surfaces the error.

### Asset handling

Note text can be stored in two ways:
1. **Inline** (`textADP` field): a string value directly in the record fields. This is used for smaller notes.
2. **Asset** (`text` field): a dictionary containing `downloadURL`, `size`, and other metadata. The text must be downloaded separately via an HTTP GET to the `downloadURL`.

When reading, always check `textADP` first. When writing, always write to `textADP`.

### Vector clocks

Bear uses binary plist vector clocks for conflict resolution. The format is a standard binary plist (`bplist00` header) encoding a dictionary with a single entry: the device name (string) mapped to a counter (integer).

When creating a new note, the CLI creates a vector clock with device name `"Bear CLI"` and counter `1`.

When updating a note, the CLI reads the existing vector clock, extracts the counter (scanning for the `0x10` byte pattern that precedes the counter byte in the binary plist), increments it by 1, and creates a new clock with `"Bear CLI"` and the incremented counter. If the existing clock cannot be parsed, it falls back to a fresh clock with counter `1`.

### Unused API method: searchNotes

The `CloudKitAPI` struct also has a public `searchNotes(query:limit:)` method that fetches all notes (with a lightweight set of fields) and filters client-side by title and tag name. This method is **not used** by any CLI command -- the `search` command uses the local cache for full-text search instead. The method exists as legacy API surface but could be removed without affecting functionality.

### HTTP error handling

- **401 or 421** status codes indicate an expired or invalid auth token. The CLI reports this as "Auth token expired" and asks the user to re-authenticate.
- **200** is the only success status code.
- All other status codes are reported as API errors with the response body (truncated to 200 characters).

---

## 3. Authentication

### Overview

Authentication works by obtaining a `ckWebAuthToken` from Apple's iCloud identity service. This is the same token that Bear Web obtains when you sign in at web.bear.app.

### Browser-based flow

The primary authentication method:

1. The CLI starts a local HTTP server on `127.0.0.1`, port `19222` (falls back to a random port if 19222 is busy).
2. The CLI opens the user's default browser to `http://localhost:{port}/`.
3. The browser loads an HTML page that:
   - Includes CloudKit JS from `https://cdn.apple-cloudkit.com/ck/2/cloudkit.js`
   - Configures CloudKit with Bear's container (`iCloud.net.shinyfrog.bear`) and API token
   - Renders an Apple Sign-In button
4. The user signs in with their Apple ID.
5. After sign-in, the page captures the `ckWebAuthToken` using two strategies:
   - **Network interception**: JavaScript monkey-patches `XMLHttpRequest.open` and `window.fetch` to inspect all outgoing request URLs for a `ckWebAuthToken=` query parameter.
   - **API trigger**: If the network interceptor didn't capture a token, the page triggers a dummy CloudKit query (`SFNoteTag` in the `Notes` zone) to force a network request that carries the token.
6. Once captured, the page POSTs the token to `http://localhost:{port}/callback` as JSON: `{"token": "..."}`.
7. The CLI server receives the token and the auth process completes.

If automatic capture fails, the page shows a manual fallback: instructions to get the token from Bear Web's DevTools, plus a text field to paste it.

### Direct token mode

Users can skip the browser flow entirely:

```
bcli auth --token '<ckWebAuthToken>'
```

### Token validation

After obtaining the token, the CLI validates it by calling `zones/list`. If the call succeeds and returns zones, the token is valid. If the status code is 401 or 421, the token is invalid or expired.

### Token storage

The token is saved to `~/.config/bear-cli/auth.json` with file permissions `0600` (owner-only read/write).

File format:
```json
{
  "ckWebAuthToken": "...",
  "ckAPIToken": "ce59f955ec47e744f720aa1d2816a4e985e472d8b859b6c7a47b81fd36646307",
  "savedAt": "2026-03-29T10:00:00Z"
}
```

The `ckAPIToken` is always the same fixed value. The `savedAt` field is ISO 8601 formatted.

### Local HTTP server details

- Built on raw BSD sockets (no third-party HTTP library)
- Server socket is set to non-blocking mode for the accept loop (50ms poll interval)
- Client sockets are set back to blocking mode with a 5-second read timeout
- Supports CORS headers for cross-origin requests from the browser
- Handles routes: `GET /` and `GET /index.html` (auth page), `POST /callback` (token submission), `GET /health` (health check), `GET /favicon.ico` (returns 204 No Content), `OPTIONS *` (CORS preflight)
- Timeout: 120 seconds total. If no token is received, the server shuts down.
- Thread-safe token storage using NSLock.

---

## 4. Data Models

### AnyCodableValue

A flexible JSON value type that handles CloudKit's polymorphic field values. It is an enum with cases:
- `string(String)`
- `int(Int64)`
- `double(Double)`
- `bool(Bool)`
- `array([AnyCodableValue])`
- `dictionary([String: AnyCodableValue])`
- `null`

It implements `Codable` with custom decoding that tries types in this order: null, Bool, Int64, Double, String, Array, Dictionary. It provides computed property accessors: `stringValue`, `intValue`, `doubleValue`, `arrayValue`, `dictValue`.

Note: `doubleValue` also returns a Double if the underlying value is an Int64 (by casting).

### CloudKit API types

These types mirror the CloudKit REST API request/response format:

- `CKZoneListResponse` -- wraps `zones: [CKZone]`
- `CKZone` -- has `zoneID: CKZoneID` and optional `syncToken: String`
- `CKZoneID` -- has `zoneName: String` and optional `ownerRecordName: String`
- `CKRecordQueryRequest` -- query with `zoneID`, `query`, optional `resultsLimit`, optional `desiredKeys`
- `CKQuery` -- has `recordType`, optional `filterBy: [CKFilter]`, optional `sortBy: [CKSort]`
- `CKFilter` -- has `fieldName`, `comparator` (e.g., "EQUALS"), and `fieldValue: CKFieldValue`
- `CKSort` -- has `fieldName` and `ascending: Bool`
- `CKFieldValue` -- has `value: AnyCodableValue` and optional `type: String`
- `CKRecordLookupRequest` -- has `records: [CKRecordRef]`, `zoneID`, optional `desiredKeys`
- `CKRecordRef` -- has `recordName: String`
- `CKRecordQueryResponse` -- has `records: [CKRecord]` and optional `continuationMarker: String`
- `CKRecordLookupResponse` -- has `records: [CKRecord]`
- `CKRecord` -- has `recordName: String`, optional `recordType`, `fields: [String: CKRecordField]` (defaults to empty dict), optional `recordChangeTag`, optional `created: CKTimestamp`, optional `modified: CKTimestamp`, optional `deleted: Bool`
- `CKTimestamp` -- has optional `timestamp: Int64` and optional `userRecordName: String`
- `CKRecordField` -- has `value: AnyCodableValue` and optional `type: String`
- `CKZoneChangesResponse` -- has `zones: [CKZoneChangeResult]`
- `CKZoneChangeResult` -- has `zoneID`, `moreComing: Bool`, `syncToken: String`, `records: [CKRecord]`

### BearNote (domain model)

Constructed from a `CKRecord`. Fields:

| Property | Type | Source field | Default |
|----------|------|-------------|---------|
| `id` | String | `recordName` | -- |
| `uniqueIdentifier` | String | `uniqueIdentifier` | falls back to `recordName` |
| `title` | String | `title` | "(untitled)" |
| `tags` | [String] | `tagsStrings` (array of strings) | [] |
| `pinned` | Bool | `pinned` == 1 | false |
| `archived` | Bool | `archived` == 1 | false |
| `trashed` | Bool | `trashed` == 1 | false |
| `locked` | Bool | `locked` == 1 | false |
| `todoCompleted` | Int | `todoCompleted` | 0 |
| `todoIncompleted` | Int | `todoIncompleted` | 0 |
| `creationDate` | Date? | `sf_creationDate` (ms epoch) | nil |
| `modificationDate` | Date? | `sf_modificationDate` (ms epoch) | nil |
| `textAssetURL` | String? | `text.downloadURL` (from dict) | nil |
| `hasFiles` | Bool | `hasFiles` == 1 | false |

### BearTag (domain model)

Constructed from a `CKRecord`. Fields:

| Property | Type | Source field | Default |
|----------|------|-------------|---------|
| `id` | String | `recordName` | -- |
| `title` | String | `title` | "(unknown)" |
| `notesCount` | Int | `notesCount` | 0 |
| `pinned` | Bool | `pinned` == 1 | false |
| `isRoot` | Bool | `isRoot` == 1 | false |

### AuthConfig

Stores authentication credentials. Codable, persisted as JSON.

| Property | Type | Description |
|----------|------|-------------|
| `ckWebAuthToken` | String (mutable) | User's iCloud session token |
| `ckAPIToken` | String | Fixed API token (always the same value) |
| `savedAt` | Date | When the config was saved |

Static members:
- `apiToken` -- the fixed API token constant
- `configDir` -- `~/.config/bear-cli/`
- `configFile` -- `~/.config/bear-cli/auth.json`
- `load()` -- reads and decodes from `configFile` (ISO 8601 date strategy)
- `save()` -- encodes and writes to `configFile` with `0600` permissions, creates config directory if needed

### CachedNote

Extended note model that includes the full text content. Used in the local cache. Codable.

| Property | Type | Description |
|----------|------|-------------|
| `recordName` | String | CloudKit record ID |
| `uniqueIdentifier` | String | Bear-style note ID |
| `title` | String | Note title |
| `tags` | [String] | Tag names |
| `pinned` | Bool | Pinned status |
| `archived` | Bool | Archived status |
| `trashed` | Bool | Trashed status |
| `locked` | Bool | Locked status |
| `creationDate` | Date? | Creation timestamp |
| `modificationDate` | Date? | Modification timestamp |
| `recordChangeTag` | String? | CloudKit version tag |
| `text` | String | Full note content (markdown) |
| `hasFiles` | Bool | Whether note has file attachments |

Can be constructed from a `CKRecord` + text string, or from explicit values (memberwise initializer).

---

## 5. Local Cache and Sync Engine

### Cache

The cache stores all notes locally as JSON for offline search and fast access.

**Location:** `~/.config/bear-cli/cache.json`

**Structure:**
```json
{
  "syncToken": "string or null",
  "lastSyncDate": "2026-03-29T10:00:00Z",
  "notes": {
    "record-name-1": { ...CachedNote... },
    "record-name-2": { ...CachedNote... }
  }
}
```

Notes are keyed by `recordName` (CloudKit record ID).

**Staleness:** The cache is considered stale if `lastSyncDate` is more than 300 seconds (5 minutes) ago, or if `lastSyncDate` is null.

**Atomic writes:** To prevent corruption, the cache is written to a temporary file (`cache.json.tmp`) first, then atomically replaced using `FileManager.replaceItemAt`.

**Date encoding:** ISO 8601 format.

**Operations:**
- `upsert(note)` -- add or replace a note by `recordName`
- `remove(recordName)` -- delete a note from the cache
- `upsertFromRecord(record, text)` -- construct a `CachedNote` from a `CKRecord` and insert it
- `markTrashed(recordName)` -- create a copy of the note with `trashed = true` and replace the original

### Sync Engine

The sync engine manages full and incremental synchronization between CloudKit and the local cache.

#### Full sync

Triggered when:
- No cache file exists
- The `--full` flag is passed to `bcli sync`
- The cache has no `syncToken`
- An incremental sync fails with an API error (fallback)

Steps:
1. Call `zones/list` to get the current `syncToken` for the Notes zone
2. Fetch all notes via paginated `records/query` (page size 200), requesting these fields: `uniqueIdentifier`, `title`, `text`, `textADP`, `tagsStrings`, `sf_creationDate`, `sf_modificationDate`, `pinned`, `archived`, `trashed`, `locked`, `hasFiles`
3. For each note, fetch the text content (try `textADP` inline first, fall back to downloading the `text` asset)
4. Build a fresh cache with all notes, the sync token, and the current timestamp
5. Save the cache atomically

Progress output in verbose mode: prints every 25 notes.

#### Incremental sync

Triggered when the cache exists and has a `syncToken`.

Steps:
1. Call `changes/zone` with the current `syncToken` (results limit 200)
2. For each record in the response:
   - If `deleted == true`: remove from cache
   - If `recordType` is `SFNote` or null: fetch text and upsert into cache
   - Skip non-SFNote record types (tags, images, etc.)
3. Update the cache's `syncToken` to the new value from the response
4. If `moreComing == true`, repeat from step 1
5. Update `lastSyncDate` and save

#### Auto-sync

The `search` and `todo` commands auto-sync before running if the cache is stale (more than 5 minutes old). This behavior is disabled with the `--no-sync` flag.

The `ensureCacheReady` method handles this: if no cache exists, it performs a full sync. If the cache exists but is stale, it performs an incremental sync (or full sync if no sync token).

#### Text fetching

The shared `fetchNoteText(from:)` method:
1. Check if `textADP` field has a string value -- if yes, return it
2. Check if `text` field has a dictionary value with a `downloadURL` -- if yes, download and return
3. Return empty string

#### SyncStats

Tracks: `added`, `updated`, `deleted`, `failed` counts.

`total` computed property returns `added + updated + deleted`.

`summary` property produces a human-readable string like `"5 new, 2 updated, 1 deleted"` or `"no changes"` if everything is zero.

---

## 6. CLI Commands

The CLI binary is called `bcli`. It uses Swift ArgumentParser for command parsing.

The top-level command `BearCLI` dispatches to subcommands. All subcommands that talk to CloudKit follow the same pattern:
1. Load auth config via `loadAuth()` (throws `authNotConfigured` if file doesn't exist)
2. Create a `CloudKitAPI` instance
3. Execute async work inside `runAsync {}` (a synchronous wrapper that uses `DispatchSemaphore` to block until the async task completes)

### 6.1 `bcli auth`

Authenticate with iCloud.

**Options:**
| Flag/Option | Description |
|-------------|-------------|
| `--token <STRING>` | Paste a ckWebAuthToken directly (skips browser) |
| `--browser` | Declared but currently unused. Intended to force browser-based authentication. The browser flow runs by default when `--token` is not provided. |

**Behavior:**
1. If `--token` is provided, use it directly
2. Otherwise, start the local auth server, open the browser, wait up to 120 seconds
3. If no token is received, print manual instructions and exit
4. Validate the token by calling `zones/list`
5. If valid, save to `~/.config/bear-cli/auth.json`
6. If invalid (401/421), print error message

**Output on success:**
```
Authenticated successfully.
Zones found: Notes
Token saved to /Users/.../.config/bear-cli/auth.json
```

### 6.2 `bcli ls`

List notes.

**Options:**
| Flag/Option | Short | Default | Description |
|-------------|-------|---------|-------------|
| `--limit <N>` | `-l` | 30 | Maximum notes to show |
| `--archived` | | false | Show archived notes |
| `--trashed` | | false | Show trashed notes |
| `--all` | | false | Fetch all notes (ignores limit, uses pagination) |
| `--tag <TAG>` | `-t` | nil | Filter by tag (case-insensitive partial match) |
| `--json` | | false | Output as JSON |

**Behavior:**
1. Query notes from CloudKit with requested fields: `uniqueIdentifier`, `title`, `sf_creationDate`, `sf_modificationDate`, `tagsStrings`, `pinned`, `todoCompleted`, `todoIncompleted`
2. If `--all`, use paginated fetch; otherwise use single query with `limit`
3. If `--tag` is specified, filter client-side (case-insensitive partial match against any tag)
4. Output in table or JSON format

**Table format:**
```
ID                                      Modified          Title
──────────────────────────────────────────────────────────────────
<uniqueIdentifier>                      2026-03-29 10:00  * My Note [tag1, tag2]
```
- ID column width: maximum of 38 or longest ID
- Pinned notes prefixed with `* `
- Tags shown in brackets after title
- Footer: `N notes`

**JSON format:**
Array of objects with: `id`, `title`, `tags`, `pinned`, `modificationDate` (Unix timestamp).

### 6.3 `bcli get <noteID>`

View a single note's content.

**Arguments:**
| Argument | Description |
|----------|-------------|
| `<noteID>` | Note ID (uniqueIdentifier or recordName) |

**Options:**
| Flag | Description |
|------|-------------|
| `--raw` | Output raw markdown without metadata header |
| `--json` | Output as JSON |

**Behavior:**
1. Resolve the note (see [Note ID Resolution](#7-note-id-resolution))
2. Fetch the note text (textADP or asset download)
3. Output in the requested format

**Default format (metadata + content):**
```
Title: My Note
ID: <uniqueIdentifier>
Tags: tag1, tag2
Modified: 2026-03-29 10:00
Pinned: yes
────────────────────────────────────────────────────────────
<full markdown content>
```
- Tags line only shown if note has tags
- Pinned line only shown if note is pinned

**Raw format:** Just the markdown text, nothing else.

**JSON format:**
Object with: `id`, `title`, `tags`, `pinned`, `text`, `creationDate` (ISO 8601), `modificationDate` (ISO 8601).

### 6.4 `bcli tags`

List all tags.

**Options:**
| Flag | Description |
|------|-------------|
| `--flat` | Show as flat list instead of tree |
| `--json` | Output as JSON |

**Behavior:**
1. Query all `SFNoteTag` records, sorted alphabetically by title (default limit: 200 records)
2. Display as tree (default), flat list, or JSON

**Tree format:**
Tags are organized hierarchically using `/` as a separator.
```
* work (5)
  ├─ projects (3)
  └─ meetings (2)
personal (10)
```
- Pinned tags prefixed with `* `
- Note count shown in parentheses
- Child tags shown with `├─` / `└─` tree connectors (2-space indent)
- Only one level of nesting is shown in the tree (first `/` split)

**Flat format:**
```
* work (5)
work/projects (3)
work/meetings (2)
personal (10)
```

**JSON format:**
Array of objects with: `title`, `notesCount`, `pinned`.

Footer in non-JSON modes: `N tags`

### 6.5 `bcli search <query>`

Full-text search across notes.

**Arguments:**
| Argument | Description |
|----------|-------------|
| `<query>` | Search term (case-insensitive) |

**Options:**
| Flag/Option | Short | Default | Description |
|-------------|-------|---------|-------------|
| `--limit <N>` | `-l` | 20 | Maximum results |
| `--json` | | false | Output as JSON |
| `--no-sync` | | false | Skip auto-sync |

**Behavior:**
1. Load or sync the local cache (auto-sync if stale, unless `--no-sync`)
2. Search all non-trashed notes in the cache, checking three fields with priority ranking:
   - **Title match** (priority 0, highest) -- case-insensitive substring match
   - **Tag match** (priority 1) -- case-insensitive substring match against any tag
   - **Body match** (priority 2, lowest) -- case-insensitive substring match in full text
3. Sort results: by match type (title first), then by modification date (newest first)
4. Limit to requested count

**Table format:**
```
  <uniqueIdentifier>  2026-03-29 10:00  My Note [tag1, tag2]
    ...context snippet around the match...
```
- Context snippets shown only for body matches (not title matches)
- Snippets are 40 characters before and after the match, with newlines replaced by spaces
- Footer: `N results`

**JSON format:**
Array of objects with: `id`, `title`, `tags`, `match` (match type as string), optional `snippet`.

### 6.6 `bcli create <title>`

Create a new note.

**Arguments:**
| Argument | Description |
|----------|-------------|
| `<title>` | Note title |

**Options:**
| Flag/Option | Short | Description |
|-------------|-------|-------------|
| `--body <TEXT>` | `-b` | Note body text |
| `--tags <TAGS>` | `-t` | Comma-separated tags |
| `--stdin` | | Read body from stdin |
| `--quiet` | | Output only the note ID |

**Behavior:**
1. Determine the body text: from `--body`, from `--stdin` (reads all input, strips trailing newline), or empty
2. Parse tags: split `--tags` value by commas, trim whitespace from each
3. Build markdown content: `# Title` on the first line, then tag hashtags (e.g., `#tag1 #tag2`) on the next line, then the body after a blank line
4. Look up existing tags. For each tag:
   - If a matching `SFNoteTag` record exists, use its `recordName`
   - If not, create a new `SFNoteTag` record
5. Submit all operations (note create + any new tag creates) in a single `records/modify` call
6. If a local cache exists, update it with the new note

**Note creation fields:**
The new SFNote record is created with all fields from the schema populated with sensible defaults: `archived=0`, `trashed=0`, `pinned=0`, `locked=0`, `encrypted=0`, `hasImages=0`, `hasFiles=0`, `hasSourceCode=0`, `todoCompleted=0`, `todoIncompleted=0`, `version=3`, `lastEditingDevice="Bear CLI"`, a fresh vector clock, and a UUID-generated `uniqueIdentifier` and `recordName` (same UUID for both).

Note: `sf_modificationDate` is set to `now + 1ms` (one millisecond after creation time).

**Output:**
```
Created: My Note
ID: <uniqueIdentifier>
Tags: tag1, tag2
```
With `--quiet`: just the uniqueIdentifier.

### 6.7 `bcli edit <noteID>`

Edit an existing note.

**Arguments:**
| Argument | Description |
|----------|-------------|
| `<noteID>` | Note ID (uniqueIdentifier or recordName) |

**Options:**
| Flag/Option | Description |
|-------------|-------------|
| `--stdin` | Replace entire note body from stdin |
| `--append <TEXT>` | Append text to the end of the note |
| `--editor` | Open in `$EDITOR` for interactive editing |

Exactly one of `--stdin`, `--append`, or `--editor` must be specified. If none is given, the CLI prints usage examples.

**Behavior:**
1. Resolve and fetch the full note record
2. Get the current text content
3. Apply the edit:
   - `--stdin`: Replace the entire content with stdin input
   - `--append`: Append text to the end, ensuring a blank line separates existing content from the appended text. Specifically: if the existing text ends with `\n`, insert one additional `\n` before the new text; if not, insert `\n\n`.
   - `--editor`: Write current text to a temp file in the system temporary directory (`FileManager.default.temporaryDirectory`, e.g., `/var/folders/.../T/bear-<first8chars>.md`), open `$EDITOR` (default: `vi`), wait for exit. If editor exits with non-zero status, abort. If content is unchanged, print "No changes made" and abort. Clean up temp file.
4. Submit the update via `records/modify`
5. Update the local cache if it exists

**Update fields:**
When updating a note, the CLI sends: `textADP`, `title` (extracted from the first `# ` line of the new text), `subtitleADP` (first non-title, non-tag, non-empty line), `vectorClock` (incremented), `sf_modificationDate` (current time), `lastEditingDevice` ("Bear CLI"), `todoCompleted` (count of `- [x]` in new text), `todoIncompleted` (count of `- [ ]` in new text).

**Output:**
```
Updated: My Note
ID: <uniqueIdentifier>
```

### 6.8 `bcli trash <noteID>`

Move a note to trash (soft delete).

**Arguments:**
| Argument | Description |
|----------|-------------|
| `<noteID>` | Note ID (uniqueIdentifier or recordName) |

**Options:**
| Flag | Description |
|------|-------------|
| `--force` | Skip confirmation prompt |

**Behavior:**
1. Resolve and fetch the full note record
2. Unless `--force`, prompt: `Trash note: "Title"? [y/N]` -- only `y` (case-insensitive) proceeds
3. Update the note via `records/modify` with: `trashed=1`, `trashedDate=now`, incremented `vectorClock`, updated `sf_modificationDate`
4. Update the local cache (mark as trashed)

**Output:**
```
Trashed: My Note
```

### 6.9 `bcli todo [noteID]`

List and toggle TODO items.

This command has two modes depending on whether a `noteID` is provided.

**Arguments:**
| Argument | Description |
|----------|-------------|
| `[noteID]` | Optional. Note ID for toggle mode. Omit for list mode. |

**Options:**
| Flag/Option | Short | Default | Description |
|-------------|-------|---------|-------------|
| `--toggle <N>` | `-t` | nil | Toggle TODO item by number (non-interactive) |
| `--json` | | false | Output as JSON |
| `--no-sync` | | false | Skip auto-sync |
| `--limit <N>` | `-l` | 30 | Maximum notes in list mode |

#### List mode (no noteID)

Shows all notes that have incomplete TODO items.

1. Load or sync the local cache
2. For each non-trashed note, count occurrences of `- [ ]` (incomplete) and `- [x]` (complete) as plain string matches
3. Filter to notes with at least one incomplete TODO
4. Sort: most incomplete items first, then by modification date (newest first)

**Table format:**
```
ID                                      TODOs       Title
----------------------------------------------------------------------
<uniqueIdentifier>                      5 left      My Task List [work]
```

**JSON format:**
Array of objects with: `id`, `title`, `tags`, `todoIncomplete`, `todoComplete`.

#### Toggle mode (with noteID)

View and toggle individual TODO items in a note.

1. Resolve and fetch the note
2. Parse all lines looking for TODO patterns:
   - `- [ ] text` or `- [ ]` (empty, incomplete)
   - `- [x] text` or `- [x]` (empty, complete)
   - Track indentation level for display
3. Display numbered list of TODO items
4. Determine which item to toggle:
   - If `--toggle N` is specified, use that number
   - Otherwise, prompt: `Enter number to toggle (or 'q' to quit):`
5. Toggle the checkbox in the specific line: replace `- [ ]` with `- [x]` or vice versa (first occurrence in the line)
6. Submit the updated text via `records/modify`
7. Update the local cache

**Display format:**
```
TODOs in: My Task List
------------------------------------------------------------
  1. [ ] Buy groceries
  2. [x] Clean kitchen
  3.   [ ] Sub-task (indented)
```
Indentation is shown as 2 spaces per indent level (divided by 2 from actual character count).

**JSON format (without --toggle):**
```json
{
  "id": "...",
  "title": "...",
  "todos": [
    {"index": 1, "text": "Buy groceries", "complete": false},
    {"index": 2, "text": "Clean kitchen", "complete": true}
  ]
}
```

### 6.10 `bcli export <outputDir>`

Export notes as markdown files to disk.

**Arguments:**
| Argument | Description |
|----------|-------------|
| `<outputDir>` | Output directory path |

**Options:**
| Flag/Option | Short | Description |
|-------------|-------|-------------|
| `--tag <TAG>` | `-t` | Filter by tag (case-insensitive partial match) |
| `--by-tag` | | Organize files into folders by first tag |
| `--frontmatter` | | Include YAML frontmatter with metadata |

**Behavior:**
1. Create the output directory if it doesn't exist
2. Fetch all notes with text content from CloudKit (paginated)
3. If `--tag` is specified, filter client-side
4. For each note:
   - Get the text (textADP or asset download)
   - Generate filename: sanitize the title (replace `/\?%*|"<>:` with `_`, trim whitespace, max 200 chars, default to "untitled") and append `.md`
   - If `--by-tag` and the note has at least one tag, create a subfolder named after the first tag (with `/` replaced by `_`)
   - If `--frontmatter`, prepend YAML metadata
   - Write the file

**YAML frontmatter format:**
```yaml
---
title: "Note Title"
id: <uniqueIdentifier>
tags: ["tag1", "tag2"]
created: 2026-03-29T10:00:00Z
modified: 2026-03-29T12:00:00Z
pinned: true
---
```
- `tags` line only included if note has tags
- `pinned` line only included if true
- Dates in ISO 8601 format
- Title quotes are escaped

**Output:**
```
Fetching note index...
Exporting 42 notes...
  10/42...
  20/42...
  30/42...
  40/42...

Exported 42 notes to ./output
```
Progress printed every 10 notes. Failed notes counted and reported separately.

### 6.11 `bcli sync`

Manually trigger a sync.

**Options:**
| Flag/Option | Short | Description |
|-------------|-------|-------------|
| `--full` | | Force a full re-sync (ignores existing cache) |
| `--verbose` | `-v` | Show per-note progress |

**Behavior:**
1. If `--full` or no cache exists: perform full sync
2. Otherwise: perform incremental sync (with fallback to full sync if API rejects the sync token)

**Output:**
```
Syncing...
Synced 150 notes (3 new, 1 updated, no changes) in 4.2s
```

In verbose mode, shows individual notes: `+ New Note` for new, `~ Updated Note` for updated.

---

## 7. Note ID Resolution

Commands that take a `<noteID>` argument (`get`, `edit`, `trash`, `todo`) use a two-step resolution process:

1. **Direct lookup:** Try `records/lookup` using the provided ID as a `recordName`. If the response contains a record with non-empty fields, use it.
2. **Identifier search:** If the direct lookup fails (returns no records or records with empty fields), fetch all notes via `queryAllNotes` and find the first record whose `uniqueIdentifier` field matches the provided ID.
3. **Full fetch:** If found by identifier search, re-fetch the record by its actual `recordName` using `records/lookup` to get all fields.

This allows users to provide either:
- The CloudKit `recordName` (a UUID)
- Bear's `uniqueIdentifier` (also a UUID, but a different one that Bear uses internally)

If neither resolves, throw `noteNotFound` error.

---

## 8. Project Structure

### Package layout

```
bear-cli/
  Package.swift
  Package.resolved
  Sources/
    bcli/
      main.swift              -- Entry point: calls BearCLI.main()
    BearCLICore/
      Exports.swift           -- BearCLI command config, loadAuth(), runAsync()
      CloudKitAPI.swift        -- REST API client
      Models.swift             -- CloudKit types and domain models
      NoteCache.swift          -- Local cache
      SyncEngine.swift         -- Sync logic
      AuthServer.swift         -- Local HTTP server for auth
      Commands/
        AuthCommand.swift      -- bcli auth
        ListNotes.swift        -- bcli ls
        GetNote.swift          -- bcli get
        ListTags.swift         -- bcli tags
        SearchNotes.swift      -- bcli search
        CreateNote.swift       -- bcli create
        EditNote.swift         -- bcli edit
        TrashNote.swift        -- bcli trash
        TodoCommand.swift      -- bcli todo
        ExportNotes.swift      -- bcli export
        SyncCommand.swift      -- bcli sync
  Tests/
    BearCLITests/
      ModelsTests.swift        -- Unit tests
```

### Package configuration

- Package name: `bear-cli`
- Platform: macOS 13+
- Targets:
  - `BearCLICore` (library) -- depends on `ArgumentParser`
  - `bcli` (executable) -- depends on `BearCLICore`
  - `BearCLITests` (test) -- depends on `BearCLICore`
- External dependency: `apple/swift-argument-parser` from 1.3.0 (resolved to 1.7.0)

### Entry point pattern

`main.swift` calls `BearCLI.main()`, which is provided by ArgumentParser's `ParsableCommand` protocol. ArgumentParser parses the command-line arguments and dispatches to the appropriate subcommand's `run()` method.

### Async execution pattern

ArgumentParser commands use synchronous `run()` methods. The CLI wraps async CloudKit calls in `runAsync {}`, which:
1. Creates a `DispatchSemaphore(value: 0)`
2. Launches a `Task` that runs the async block
3. Calls `semaphore.wait()` to block the main thread
4. Re-throws any error from the async block

### Version tracking

The version string (`"0.3.3"`) is set in `BearCLI.configuration.version` in `Exports.swift`.

---

## 9. CI/CD and Release

### Release workflow

Triggered by pushing a git tag matching `v*` (e.g., `v0.3.3`).

**Steps:**
1. Runs on `macos-15` GitHub Actions runner
2. Checks out the repository
3. Builds a universal binary (arm64 + x86_64): `swift build -c release --arch arm64 --arch x86_64`
4. Packages the binary:
   - Creates `dist/` directory
   - Copies binary from `.build/apple/Products/Release/bcli`
   - Creates `bcli-macos-universal.tar.gz`
   - Generates SHA-256 checksum file (`bcli-macos-universal.tar.gz.sha256`)
5. Creates a GitHub Release (using `softprops/action-gh-release@v2`) with:
   - The tarball and checksum file as release assets
   - Auto-generated release notes

### Installation methods

**From release binary:**
```
curl -L https://github.com/asabirov/bcli/releases/latest/download/bcli-macos-universal.tar.gz -o bcli.tar.gz
tar xzf bcli.tar.gz
mv bcli ~/.local/bin/bcli
rm bcli.tar.gz
```

**From source:**
```
git clone https://github.com/asabirov/bcli.git
cd bcli
swift build -c release
cp .build/release/bcli ~/.local/bin/bcli
```

---

## 10. Testing

### Test target

Tests are in `Tests/BearCLITests/ModelsTests.swift`. They test the model layer and cache -- no network calls.

### Test coverage

**AnyCodableValue tests:**
- Encoding/decoding round-trip for all value types (string, int, double, bool, array, dictionary, null)
- `doubleValue` accessor returns Double from Int64 values
- Null returns nil for typed accessors

**BearNote tests:**
- Construction from a fully populated CKRecord -- verifies all fields map correctly
- Construction from an empty CKRecord (no fields) -- verifies defaults: title = "(untitled)", empty tags, all booleans false, all dates nil

**BearTag tests:**
- Construction from a CKRecord with all fields

**NoteCache tests:**
- `isStale` returns true when `lastSyncDate` is nil
- `isStale` returns false when synced within 300 seconds
- `isStale` returns true when synced more than 300 seconds ago
- `upsert` and `remove` operations work correctly
- `markTrashed` creates a copy with `trashed = true` and preserves all other fields

**CKRecord decoding tests:**
- JSON decoding with various field configurations
- Handling of records with missing optional fields

**SyncStats tests:**
- Empty stats produce `"no changes"` summary
- Non-empty stats produce correctly formatted summary (e.g., `"5 new, 2 updated, 1 deleted"`)

---

## Appendix: Error Types

### BearCLIError

| Case | Message | When |
|------|---------|------|
| `authExpired` | "Auth token expired. Run \`bcli auth\` to re-authenticate." | HTTP 401 or 421 from CloudKit |
| `authNotConfigured` | "Not authenticated. Run \`bcli auth\` first." | Auth config file doesn't exist |
| `apiError(code, body)` | "CloudKit API error (N): ..." | Non-200 HTTP status (truncated to 200 chars) |
| `networkError(msg)` | "Network error: ..." | Invalid response, download failure, UTF-8 decode failure |
| `invalidURL(url)` | "Invalid URL: ..." | Malformed asset download URL |
| `noteNotFound(id)` | "Note not found: ..." | Note ID resolution failed |

### AuthServerError

| Case | Message | When |
|------|---------|------|
| `socketCreationFailed(msg)` | "Socket creation failed: ..." | BSD socket creation returns -1 |
| `bindFailed(msg)` | "Bind failed: ..." | Cannot bind to port 19222 or any fallback |

---

## Appendix: File Locations

| Purpose | Path |
|---------|------|
| Auth config | `~/.config/bear-cli/auth.json` |
| Note cache | `~/.config/bear-cli/cache.json` |
| Cache temp file | `~/.config/bear-cli/cache.json.tmp` |
| Editor temp file | `{system-temp-dir}/bear-<noteID-prefix>.md` (via `FileManager.default.temporaryDirectory`) |
