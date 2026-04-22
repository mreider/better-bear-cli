import ArgumentParser
import Foundation

public struct ContextCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "context",
        abstract: "Manage a curated context library for LLMs",
        subcommands: [
            ContextInit.self,
            ContextSync.self,
            ContextIndex.self,
            ContextFetch.self,
            ContextSearch.self,
            ContextAdd.self,
            ContextRemove.self,
            ContextStatus.self,
            ContextImport.self,
            ContextIngest.self,
            ContextTriage.self,
            ContextPush.self,
            ContextRemoveExternal.self,
            ContextSetPrefix.self,
        ]
    )
    public init() {}
}

// MARK: - Init

struct ContextInit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Set up a context library"
    )

    @Option(name: .long, help: "Output directory (default: ~/.bear-context)")
    var dir: String?

    @Option(name: .long, help: "Tag prefix for qualifying notes (default: context)")
    var tagPrefix: String?

    @Flag(name: .long, help: "Also match notes with context: true in front matter")
    var frontmatter: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let dir = self.dir
        let tagPrefix = self.tagPrefix
        let useFm = self.frontmatter || true // default true
        let json = self.json

        let config = try engine.initialize(
            contextDir: dir,
            tagPrefix: tagPrefix,
            useFrontMatter: useFm
        )

        if json {
            let output: [String: Any] = [
                "context_dir": config.contextDir,
                "tag_prefix": config.tagPrefix,
                "use_frontmatter": config.useFrontMatter,
                "status": "initialized",
            ]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) { print(str) }
        } else {
            print("Context library initialized.")
            print("  Directory: \(config.resolvedDir.path)")
            print("  Tag prefix: #\(config.tagPrefix)")
            print("  Front matter: \(config.useFrontMatter ? "enabled" : "disabled")")
            print("\nTag notes with #\(config.tagPrefix) and run `bcli context sync`.")
        }
    }
}

// MARK: - Sync

struct ContextSync: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync qualifying Bear notes to the context library"
    )

    @Flag(name: .long, help: "Force full re-sync")
    var force: Bool = false

    @Flag(name: .shortAndLong, help: "Show per-note progress")
    var verbose: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let force = self.force
        let verbose = self.verbose
        let json = self.json

        try runAsync {
            let result = try await engine.sync(force: force, verbose: verbose)

            if json {
                let output = result.toDict()
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                var parts: [String] = []
                if result.added > 0 { parts.append("\(result.added) added") }
                if result.updated > 0 { parts.append("\(result.updated) updated") }
                if result.removed > 0 { parts.append("\(result.removed) removed") }
                if result.unchanged > 0 { parts.append("\(result.unchanged) unchanged") }
                let summary = parts.isEmpty ? "no changes" : parts.joined(separator: ", ")
                print("Synced: \(summary). \(result.totalFiles) files, ~\(result.totalTokens) tokens.")
                if result.inboxCount > 0 {
                    print("\(result.inboxCount) file(s) in inbox awaiting triage.")
                }
            }
        }
    }
}

// MARK: - Index

struct ContextIndex: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Show the context library index"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let json = self.json

        let (content, ageSeconds, stale, inboxCount) = try engine.index()

        if json {
            let output: [String: Any] = [
                "content": content,
                "cache_age_seconds": ageSeconds,
                "stale": stale,
                "inbox_count": inboxCount,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) { print(str) }
        } else {
            print(content)
            if stale {
                fputs("Warning: Bear cache is stale (\(ageSeconds)s). Run `bcli context sync`.\n", stderr)
            }
        }
    }
}

// MARK: - Fetch

struct ContextFetch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fetch",
        abstract: "Load content of specific context files"
    )

    @Argument(help: "File paths relative to context directory")
    var paths: [String]

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let paths = self.paths
        let json = self.json

        let results = try engine.fetch(paths: paths)

        if json {
            if let data = try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) { print(str) }
        } else {
            for result in results {
                if let error = result["error"] as? String {
                    fputs("\(result["path"] ?? "?"): \(error)\n", stderr)
                } else if let content = result["content"] as? String {
                    print("--- \(result["path"] ?? "?") ---")
                    print(content)
                }
            }
        }
    }
}

// MARK: - Search

struct ContextSearch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search across the context library"
    )

    @Argument(help: "Search query")
    var query: String

    @Option(name: .long, help: "Maximum results (default: 5)")
    var limit: Int = 5

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let query = self.query
        let limit = self.limit
        let json = self.json

        let results = try engine.search(query: query, limit: limit)

        if json {
            let output = results.map { r -> [String: Any] in
                return [
                    "filename": r.filename, "origin": r.origin,
                    "title": r.title, "snippet": r.snippet,
                    "estimated_tokens": r.estimatedTokens,
                ]
            }
            if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) { print(str) }
        } else {
            if results.isEmpty {
                print("No results for \"\(query)\".")
            } else {
                for r in results {
                    print("\(r.filename) [\(r.origin)] — \(r.title)")
                    print("  \(r.snippet)")
                    print()
                }
            }
        }
    }
}

// MARK: - Add

struct ContextAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a Bear note to the context library"
    )

    @Argument(help: "Note ID (uniqueIdentifier)")
    var noteID: String

    @Option(name: .long, help: "Sub-tag (e.g., 'jira' → #context/jira)")
    var subtag: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let noteID = self.noteID
        let subtag = self.subtag
        let json = self.json

        try runAsync {
            let result = try await engine.addNote(noteID: noteID, subtag: subtag)

            if json {
                var output = result.toDict()
                output["note_id"] = noteID
                output["action"] = "added"
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                print("Added to context library. \(result.totalFiles) files, ~\(result.totalTokens) tokens.")
            }
        }
    }
}

// MARK: - Remove

struct ContextRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a Bear note from the context library"
    )

    @Argument(help: "Note ID (uniqueIdentifier)")
    var noteID: String

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let noteID = self.noteID
        let json = self.json

        try runAsync {
            let result = try await engine.removeNote(noteID: noteID)

            if json {
                var output = result.toDict()
                output["note_id"] = noteID
                output["action"] = "removed"
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                print("Removed from context library. \(result.totalFiles) files, ~\(result.totalTokens) tokens.")
            }
        }
    }
}

// MARK: - Status

struct ContextStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show context library health and stats"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let json = self.json

        let result = try engine.status()

        if json {
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) { print(str) }
        } else {
            let bearCount = result["bear_notes"] as? Int ?? 0
            let externalCount = result["external_files"] as? Int ?? 0
            let inboxCount = result["inbox_count"] as? Int ?? 0
            let totalTokens = result["total_tokens"] as? Int ?? 0
            let lastSync = result["last_sync"] as? String ?? "never"
            let stale = result["stale"] as? Bool ?? true

            print("Context Library Status")
            print("  Bear notes:     \(bearCount)")
            print("  External files: \(externalCount)")
            print("  Inbox:          \(inboxCount)")
            print("  Total tokens:   ~\(totalTokens)")
            print("  Last sync:      \(lastSync)\(stale ? " (stale)" : "")")

            if let groups = result["groups"] as? [String: Int], !groups.isEmpty {
                print("  Groups:")
                for (name, count) in groups.sorted(by: { $0.key < $1.key }) {
                    print("    \(name): \(count)")
                }
            }

            if let warnings = result["warnings"] as? [String], !warnings.isEmpty {
                print("  Warnings:")
                for w in warnings { print("    - \(w)") }
            }
        }
    }
}

// MARK: - Import

struct ContextImport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import an external file into the context library"
    )

    @Argument(help: "Source file path (omit if using --stdin)")
    var filePath: String?

    @Option(name: .long, help: "Target filename in external/ (defaults to source basename)")
    var filename: String?

    @Option(name: .long, help: "Group label for the file")
    var group: String?

    @Option(name: .long, help: "Source description (e.g., URL, tool name)")
    var source: String?

    @Option(name: .long, help: "Short summary of the content")
    var summary: String?

    @Flag(name: .long, help: "Read content from stdin")
    var stdin: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let json = self.json

        let content: String
        let targetFilename: String

        if self.stdin {
            // Read from stdin
            let data = FileHandle.standardInput.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                throw ContextError.fileNotFound("stdin (no input)")
            }
            content = text
            guard let name = self.filename else {
                throw ContextError.fileNotFound("--filename is required when using --stdin")
            }
            targetFilename = name.hasSuffix(".md") ? name : "\(name).md"
        } else {
            guard let path = self.filePath else {
                throw ContextError.fileNotFound("No file path provided. Use a file path or --stdin.")
            }
            let expandedPath = NSString(string: path).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)
            content = try String(contentsOf: url, encoding: .utf8)
            let basename = url.lastPathComponent
            targetFilename = self.filename ?? (basename.hasSuffix(".md") ? basename : "\(basename).md")
        }

        let result = try engine.importExternal(
            filename: targetFilename,
            content: content,
            group: self.group,
            source: self.source,
            summary: self.summary
        )

        if json {
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) { print(str) }
        } else {
            print("Imported \(result["filename"] ?? targetFilename) (~\(result["tokens"] ?? 0) tokens)")
        }
    }
}

// MARK: - Ingest

struct ContextIngest: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ingest",
        abstract: "Scan the inbox and list untriaged files"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let json = self.json

        let results = try engine.ingestInbox()

        if json {
            if let data = try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) { print(str) }
        } else {
            if results.isEmpty {
                print("Inbox is empty.")
            } else {
                print("\(results.count) file(s) in inbox:\n")
                for item in results {
                    let name = item["filename"] as? String ?? "?"
                    let size = item["size"] as? Int ?? 0
                    let preview = item["preview"] as? String ?? ""
                    let firstLine = preview.components(separatedBy: "\n").first ?? ""
                    print("  \(name) (\(size) bytes)")
                    print("    \(String(firstLine.prefix(80)))")
                    print()
                }
            }
        }
    }
}

// MARK: - Triage

struct ContextTriage: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "triage",
        abstract: "Triage an inbox file: keep, push to Bear, or discard"
    )

    @Argument(help: "Filename in inbox/")
    var filename: String

    @Argument(help: "Action: keep, push_to_bear, or discard")
    var action: String

    @Option(name: .long, help: "Group label (used with keep)")
    var group: String?

    @Option(name: .long, help: "Sub-tag for Bear (used with push_to_bear)")
    var subtag: String?

    @Option(name: .long, help: "Short summary (used with keep)")
    var summary: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let filename = self.filename
        let action = self.action
        let group = self.group
        let subtag = self.subtag
        let summary = self.summary
        let json = self.json

        try runAsync {
            let result = try await engine.triageInboxFile(
                filename: filename,
                action: action,
                group: group,
                subtag: subtag,
                summary: summary
            )

            if json {
                if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                let resultAction = result["action"] as? String ?? action
                print("Triaged \(filename): \(resultAction)")
                if let target = result["filename"] as? String, target != filename {
                    print("  → \(target)")
                }
            }
        }
    }
}

// MARK: - Push

struct ContextPush: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "Push an external file to Bear as a new note"
    )

    @Argument(help: "Filename in external/")
    var filename: String

    @Option(name: .long, help: "Sub-tag (e.g., 'jira' → #context/jira)")
    var subtag: String?

    @Option(name: .long, help: "Override note title")
    var title: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let filename = self.filename
        let subtag = self.subtag
        let title = self.title
        let json = self.json

        try runAsync {
            let result = try await engine.pushToBear(
                filename: filename,
                subtag: subtag,
                title: title
            )

            if json {
                if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                let bearTitle = result["bear_title"] as? String ?? filename
                let bearTag = result["bear_tag"] as? String ?? "#context"
                print("Pushed \(filename) to Bear as \"\(bearTitle)\" with \(bearTag)")
            }
        }
    }
}

// MARK: - Remove External

struct ContextRemoveExternal: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove-external",
        abstract: "Remove a file from the external directory"
    )

    @Argument(help: "Filename in external/")
    var filename: String

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let engine = ContextEngine(api: api)
        let filename = self.filename
        let json = self.json

        let result = try engine.removeExternal(filename: filename)

        if json {
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) { print(str) }
        } else {
            print("Removed external/\(filename)")
        }
    }
}

// MARK: - Set Prefix

struct ContextSetPrefix: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-prefix",
        abstract: "Change the context-library tag prefix and re-tag existing notes"
    )

    @Argument(help: "New tag prefix (without #) — e.g. 10-projects")
    var newPrefix: String

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let newPrefix = self.newPrefix
        let json = self.json

        try runAsync {
            guard ContextConfig.exists() else {
                throw ContextError.notInitialized
            }
            var config = try ContextConfig.load()
            let oldPrefix = config.tagPrefix

            if oldPrefix == newPrefix {
                if json {
                    let out: [String: Any] = [
                        "old_prefix": oldPrefix, "new_prefix": newPrefix,
                        "notes_updated": 0, "changed": false, "reason": "already set",
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: out, options: .prettyPrinted),
                       let s = String(data: data, encoding: .utf8) { print(s) }
                } else {
                    print("Tag prefix is already '\(newPrefix)' — nothing to do.")
                }
                return
            }

            // Scan all notes; rename tag prefix on those that carry it.
            let allRecords = try await api.queryAllNotes(
                desiredKeys: ["uniqueIdentifier", "tagsStrings"]
            )

            var matchingRecordNames: [String] = []
            for stub in allRecords {
                guard let arr = stub.fields["tagsStrings"]?.value.arrayValue else { continue }
                let tags = arr.compactMap { $0.stringValue }
                let hasMatch = tags.contains { t in
                    t == oldPrefix || t.hasPrefix(oldPrefix + "/")
                }
                if hasMatch {
                    matchingRecordNames.append(stub.recordName)
                }
            }

            var updated = 0
            for recName in matchingRecordNames {
                guard let full = try await api.lookupRecords(ids: [recName]).first else { continue }

                var body = ""
                if let t = full.fields["textADP"]?.value.stringValue {
                    body = t
                } else if let url = BearNote(from: full).textAssetURL {
                    body = try await api.downloadAsset(url: url)
                }

                let newBody = TagParser.renameTagPrefix(
                    in: body, from: oldPrefix, to: newPrefix
                )

                // Re-derive the full tag index from the renamed body so the
                // sidebar matches. This matches EditNote's auto-re-index.
                let bodyTags = TagParser.extractTags(from: newBody)
                let indexed = TagParser.expandAncestors(bodyTags)
                let nameToUUID = try await api.ensureTagsExist(names: indexed)
                let tagUUIDs = indexed.compactMap { nameToUUID[$0] }

                _ = try await api.updateNote(
                    record: full, newText: newBody,
                    tagUUIDs: tagUUIDs, tagStrings: indexed
                )
                updated += 1
            }

            // Persist the new prefix in the context config.
            config.tagPrefix = newPrefix
            try config.save()

            if json {
                let out: [String: Any] = [
                    "old_prefix": oldPrefix,
                    "new_prefix": newPrefix,
                    "notes_updated": updated,
                    "changed": true,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: out, options: .prettyPrinted),
                   let s = String(data: data, encoding: .utf8) { print(s) }
            } else {
                print("Renamed tag prefix: '\(oldPrefix)' → '\(newPrefix)'")
                print("Updated \(updated) note(s).")
                print("")
                print("Run `bcli context sync` to refresh the library.")
            }
        }
    }
}
