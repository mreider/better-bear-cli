import Foundation

// MARK: - Configuration

public struct ContextConfig: Codable {
    public var contextDir: String
    public var tagPrefix: String
    public var useFrontMatter: Bool
    public var warningAfterSeconds: Int
    public var staleAfterSeconds: Int

    public static let defaultDir = "~/.bear-context"
    public static let defaultTagPrefix = "context"

    public init(
        contextDir: String = defaultDir,
        tagPrefix: String = defaultTagPrefix,
        useFrontMatter: Bool = true,
        warningAfterSeconds: Int = 3600,
        staleAfterSeconds: Int = 86400
    ) {
        self.contextDir = contextDir
        self.tagPrefix = tagPrefix
        self.useFrontMatter = useFrontMatter
        self.warningAfterSeconds = warningAfterSeconds
        self.staleAfterSeconds = staleAfterSeconds
    }

    public static var configFile: URL {
        AuthConfig.configDir.appendingPathComponent("context.json")
    }

    public static func exists() -> Bool {
        FileManager.default.fileExists(atPath: configFile.path)
    }

    public static func load() throws -> ContextConfig {
        let data = try Data(contentsOf: configFile)
        return try JSONDecoder().decode(ContextConfig.self, from: data)
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: AuthConfig.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Self.configFile, options: .atomic)
    }

    public var resolvedDir: URL {
        let expanded = NSString(string: contextDir).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}

// MARK: - Metadata

public struct ContextMeta: Codable {
    public var lastSyncDate: Date?
    public var configSnapshot: ConfigSnapshot
    public var bearNotes: [String: ContextEntry]

    public struct ConfigSnapshot: Codable, Equatable {
        public var tagPrefix: String
        public var useFrontMatter: Bool
    }

    public init(config: ContextConfig) {
        self.lastSyncDate = nil
        self.configSnapshot = ConfigSnapshot(
            tagPrefix: config.tagPrefix,
            useFrontMatter: config.useFrontMatter
        )
        self.bearNotes = [:]
    }

    public static func load(from dir: URL) throws -> ContextMeta {
        let file = dir.appendingPathComponent(".context-meta.json")
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ContextMeta.self, from: data)
    }

    public func save(to dir: URL) throws {
        let file = dir.appendingPathComponent(".context-meta.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        let tmp = dir.appendingPathComponent(".context-meta.json.tmp")
        try data.write(to: tmp)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
    }
}

public struct ContextEntry: Codable {
    public let recordName: String
    public let uniqueIdentifier: String
    public let filename: String
    public let title: String
    public let tags: [String]
    public let recordChangeTag: String?
    public let charCount: Int
    public let estimatedTokens: Int
    public let lastSyncedAt: Date
}

// MARK: - Result Types

public struct ContextSyncResult {
    public var added: Int = 0
    public var updated: Int = 0
    public var removed: Int = 0
    public var unchanged: Int = 0
    public var totalFiles: Int = 0
    public var totalTokens: Int = 0
    public var inboxCount: Int = 0

    public func toDict() -> [String: Any] {
        return [
            "added": added, "updated": updated, "removed": removed,
            "unchanged": unchanged, "total_files": totalFiles,
            "total_tokens": totalTokens, "inbox_count": inboxCount,
        ]
    }
}

public struct ContextSearchResult {
    public let filename: String
    public let origin: String
    public let title: String
    public let snippet: String
    public let estimatedTokens: Int
}

// MARK: - Engine

public struct ContextEngine {
    public let api: CloudKitAPI

    public init(api: CloudKitAPI) {
        self.api = api
    }

    // MARK: - Initialize

    public func initialize(
        contextDir: String? = nil,
        tagPrefix: String? = nil,
        useFrontMatter: Bool = true
    ) throws -> ContextConfig {
        let config = ContextConfig(
            contextDir: contextDir ?? ContextConfig.defaultDir,
            tagPrefix: tagPrefix ?? ContextConfig.defaultTagPrefix,
            useFrontMatter: useFrontMatter
        )

        let dir = config.resolvedDir
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("bear"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("external"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("inbox"), withIntermediateDirectories: true)

        try config.save()

        // Write initial meta
        let meta = ContextMeta(config: config)
        try meta.save(to: dir)

        return config
    }

    // MARK: - Sync

    public func sync(force: Bool = false, verbose: Bool = false) async throws -> ContextSyncResult {
        guard ContextConfig.exists() else {
            throw ContextError.notInitialized
        }
        let config = try ContextConfig.load()
        let dir = config.resolvedDir

        // Ensure NoteCache is fresh (force NoteCache sync if context force-sync requested)
        let syncEngine = SyncEngine(api: api)
        let cache: NoteCache
        if force {
            let (c, _) = try await syncEngine.sync(force: false, verbose: verbose)
            cache = c
        } else {
            cache = try await syncEngine.ensureCacheReady(verbose: verbose)
        }

        // Load existing meta (needed for reconciliation even on force)
        var meta: ContextMeta
        let currentSnapshot = ContextMeta.ConfigSnapshot(
            tagPrefix: config.tagPrefix,
            useFrontMatter: config.useFrontMatter
        )

        let existingMeta = try? ContextMeta.load(from: dir)
        if let existing = existingMeta {
            meta = existing
            // Config changed → keep entries for cleanup but force re-download
            if meta.configSnapshot != currentSnapshot {
                if verbose { print("Config changed, rebuilding...") }
            }
        } else {
            meta = ContextMeta(config: config)
        }

        // On force: reset change tags so everything gets rewritten
        if force {
            for key in meta.bearNotes.keys {
                let entry = meta.bearNotes[key]!
                meta.bearNotes[key] = ContextEntry(
                    recordName: entry.recordName,
                    uniqueIdentifier: entry.uniqueIdentifier,
                    filename: entry.filename,
                    title: entry.title,
                    tags: entry.tags,
                    recordChangeTag: nil,
                    charCount: entry.charCount,
                    estimatedTokens: entry.estimatedTokens,
                    lastSyncedAt: entry.lastSyncedAt
                )
            }
        }

        // Filter qualifying notes
        let qualifying = qualifyingNotes(from: cache, config: config)
        let qualifyingByRecord = Dictionary(uniqueKeysWithValues: qualifying.map { ($0.recordName, $0) })

        var result = ContextSyncResult()
        let bearDir = dir.appendingPathComponent("bear")

        // Add or update
        for (recordName, note) in qualifyingByRecord {
            if let existing = meta.bearNotes[recordName] {
                if existing.recordChangeTag != note.recordChangeTag || force {
                    // Updated
                    try writeNoteFile(note: note, to: bearDir, filename: existing.filename)
                    meta.bearNotes[recordName] = makeEntry(note: note, filename: existing.filename)
                    result.updated += 1
                    if verbose { print("  ~ \(note.title)") }
                } else {
                    result.unchanged += 1
                }
            } else {
                // New
                let filename = uniqueFilename(for: note, existing: meta.bearNotes)
                try writeNoteFile(note: note, to: bearDir, filename: filename)
                meta.bearNotes[recordName] = makeEntry(note: note, filename: filename)
                result.added += 1
                if verbose { print("  + \(note.title)") }
            }
        }

        // Remove notes no longer qualifying (tracked in meta)
        for (recordName, entry) in meta.bearNotes {
            if qualifyingByRecord[recordName] == nil {
                let filePath = bearDir.appendingPathComponent(entry.filename)
                try? FileManager.default.removeItem(at: filePath)
                meta.bearNotes.removeValue(forKey: recordName)
                result.removed += 1
                if verbose { print("  - \(entry.title)") }
            }
        }

        // Clean up orphaned files on disk not tracked in meta
        let trackedFilenames = Set(meta.bearNotes.values.map { $0.filename })
        if let filesOnDisk = try? FileManager.default.contentsOfDirectory(at: bearDir, includingPropertiesForKeys: nil) {
            for file in filesOnDisk where file.pathExtension == "md" {
                if !trackedFilenames.contains(file.lastPathComponent) {
                    try? FileManager.default.removeItem(at: file)
                    result.removed += 1
                    if verbose { print("  - (orphan) \(file.lastPathComponent)") }
                }
            }
        }

        // Compute totals
        result.totalFiles = meta.bearNotes.count + countFiles(in: dir.appendingPathComponent("external"))
        result.totalTokens = meta.bearNotes.values.reduce(0) { $0 + $1.estimatedTokens }
            + tokenEstimateForDir(dir.appendingPathComponent("external"))
        result.inboxCount = countFiles(in: dir.appendingPathComponent("inbox"))

        // Update meta
        meta.lastSyncDate = Date()
        meta.configSnapshot = currentSnapshot
        try meta.save(to: dir)

        // Regenerate index
        try generateIndex(config: config, meta: meta, dir: dir)

        return result
    }

    // MARK: - Index

    public func index() throws -> (content: String, cacheAgeSeconds: Int, stale: Bool, inboxCount: Int) {
        let config = try ContextConfig.load()
        let dir = config.resolvedDir
        let indexFile = dir.appendingPathComponent("index.md")

        guard FileManager.default.fileExists(atPath: indexFile.path) else {
            throw ContextError.neverSynced
        }

        let content = try String(contentsOf: indexFile, encoding: .utf8)
        let meta = try ContextMeta.load(from: dir)

        let ageSeconds: Int
        let stale: Bool
        if let lastSync = meta.lastSyncDate {
            ageSeconds = Int(Date().timeIntervalSince(lastSync))
            stale = ageSeconds > config.staleAfterSeconds
        } else {
            ageSeconds = -1
            stale = true
        }

        let inboxCount = countFiles(in: dir.appendingPathComponent("inbox"))
        return (content, ageSeconds, stale, inboxCount)
    }

    // MARK: - Fetch

    public func fetch(paths: [String]) throws -> [[String: Any]] {
        let config = try ContextConfig.load()
        let dir = config.resolvedDir
        var results: [[String: Any]] = []

        for path in paths {
            // Prevent path traversal
            guard !path.contains("..") else {
                results.append(["path": path, "error": "invalid path"])
                continue
            }
            let fileURL = dir.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                results.append(["path": path, "error": "not found"])
                continue
            }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            results.append(["path": path, "content": content, "tokens": content.count / 4])
        }
        return results
    }

    // MARK: - Search

    public func search(query: String, limit: Int = 5) throws -> [ContextSearchResult] {
        let config = try ContextConfig.load()
        let dir = config.resolvedDir
        let lowerQuery = query.lowercased()
        var results: [ContextSearchResult] = []

        for subdir in ["bear", "external", "inbox"] {
            let subdirURL = dir.appendingPathComponent(subdir)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: subdirURL, includingPropertiesForKeys: nil
            ) else { continue }

            for file in files where file.pathExtension == "md" {
                let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                if content.lowercased().contains(lowerQuery) {
                    let title = extractTitle(from: content) ?? file.deletingPathExtension().lastPathComponent
                    let snippet = extractSnippet(from: content, query: lowerQuery)
                    results.append(ContextSearchResult(
                        filename: "\(subdir)/\(file.lastPathComponent)",
                        origin: subdir,
                        title: title,
                        snippet: snippet,
                        estimatedTokens: content.count / 4
                    ))
                }
                if results.count >= limit { return results }
            }
        }
        return results
    }

    // MARK: - Add / Remove

    public func addNote(noteID: String, subtag: String? = nil) async throws -> ContextSyncResult {
        let config = try ContextConfig.load()
        let record = try await findNote(noteID: noteID)
        let text = try await SyncEngine(api: api).fetchNoteText(from: record)

        let tagName = subtag != nil ? "\(config.tagPrefix)/\(subtag!)" : config.tagPrefix
        let tagMarker = tagName.contains(" ") ? "#\(tagName)#" : "#\(tagName)"

        if text.contains(tagMarker) {
            // Already tagged, just sync
            return try await sync()
        }

        // Insert tag after title line (same pattern as TagAdd)
        let lines = text.components(separatedBy: "\n")
        var newLines = lines
        var insertIdx = 1
        for i in 1..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") && !trimmed.hasPrefix("# ") && !trimmed.hasPrefix("##") {
                insertIdx = i + 1
            } else if !trimmed.isEmpty {
                break
            } else {
                insertIdx = i + 1
            }
        }
        newLines.insert(tagMarker, at: insertIdx)
        let newText = newLines.joined(separator: "\n")

        _ = try await api.updateNote(record: record, newText: newText)
        // Force sync to pick up the change
        return try await sync(force: true)
    }

    public func removeNote(noteID: String) async throws -> ContextSyncResult {
        let config = try ContextConfig.load()
        let record = try await findNote(noteID: noteID)
        let text = try await SyncEngine(api: api).fetchNoteText(from: record)

        // Remove all context tags
        let lines = text.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") && !trimmed.hasPrefix("# ") && !trimmed.hasPrefix("##") {
                let tag = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
                return !tag.hasPrefix(config.tagPrefix)
            }
            return true
        }
        let newText = filtered.joined(separator: "\n")

        if newText != text {
            _ = try await api.updateNote(record: record, newText: newText)
        }
        return try await sync(force: true)
    }

    // MARK: - Status

    public func status() throws -> [String: Any] {
        let config = try ContextConfig.load()
        let dir = config.resolvedDir
        let meta = try ContextMeta.load(from: dir)

        let bearCount = meta.bearNotes.count
        let bearTokens = meta.bearNotes.values.reduce(0) { $0 + $1.estimatedTokens }
        let externalCount = countFiles(in: dir.appendingPathComponent("external"))
        let externalTokens = tokenEstimateForDir(dir.appendingPathComponent("external"))
        let inboxCount = countFiles(in: dir.appendingPathComponent("inbox"))

        let ageSeconds: Int
        let stale: Bool
        if let lastSync = meta.lastSyncDate {
            ageSeconds = Int(Date().timeIntervalSince(lastSync))
            stale = ageSeconds > config.staleAfterSeconds
        } else {
            ageSeconds = -1
            stale = true
        }

        // Group bear notes by subtag
        var groups: [String: Int] = [:]
        for entry in meta.bearNotes.values {
            let group = entry.tags
                .first { $0.hasPrefix(config.tagPrefix) }
                .flatMap { tag in
                    let parts = tag.split(separator: "/", maxSplits: 2)
                    return parts.count > 1 ? String(parts[1]) : nil
                } ?? "general"
            groups[group, default: 0] += 1
        }

        var warnings: [String] = []
        if stale { warnings.append("Bear cache is stale (\(ageSeconds)s since last sync)") }
        if inboxCount > 0 { warnings.append("\(inboxCount) untriaged file(s) in inbox") }

        // Check for oversized files
        for entry in meta.bearNotes.values where entry.estimatedTokens > 20000 {
            warnings.append("\(entry.filename) is large (~\(entry.estimatedTokens) tokens)")
        }

        return [
            "bear_notes": bearCount,
            "bear_tokens": bearTokens,
            "external_files": externalCount,
            "external_tokens": externalTokens,
            "inbox_count": inboxCount,
            "total_files": bearCount + externalCount,
            "total_tokens": bearTokens + externalTokens,
            "last_sync": meta.lastSyncDate.map { ISO8601DateFormatter().string(from: $0) } as Any,
            "cache_age_seconds": ageSeconds,
            "stale": stale,
            "groups": groups,
            "warnings": warnings,
            "tag_prefix": config.tagPrefix,
            "context_dir": config.contextDir,
        ]
    }

    // MARK: - Private Helpers

    private func qualifyingNotes(from cache: NoteCache, config: ContextConfig) -> [CachedNote] {
        let tagMarker = "#\(config.tagPrefix)"
        return cache.notes.values.filter { note in
            guard !note.trashed && !note.archived else { return false }

            // Check indexed tags
            let hasTag = note.tags.contains { $0.hasPrefix(config.tagPrefix) }
            if hasTag { return true }

            // Also check note text for tag markers (CloudKit may not have re-indexed yet)
            for line in note.text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == tagMarker || trimmed.hasPrefix(tagMarker + "/") || trimmed.hasPrefix(tagMarker + "#") {
                    return true
                }
            }

            // Check front matter
            if config.useFrontMatter {
                let (fm, _) = FrontMatter.parse(note.text)
                if fm?.get("context")?.lowercased() == "true" { return true }
            }

            return false
        }
    }

    private func slugify(_ title: String) -> String {
        var slug = title.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        slug = slug.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        // Collapse multiple hyphens
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "untitled" }
        if slug.count > 80 { slug = String(slug.prefix(80)) }
        return slug
    }

    private func uniqueFilename(for note: CachedNote, existing: [String: ContextEntry]) -> String {
        let base = slugify(note.title)
        let candidate = "\(base).md"

        let usedNames = Set(existing.values.map { $0.filename })
        if !usedNames.contains(candidate) { return candidate }

        // Append short hash of recordName
        let hash = String(note.recordName.hashValue, radix: 16, uppercase: false)
        let suffix = String(hash.suffix(6))
        return "\(base)-\(suffix).md"
    }

    private func writeNoteFile(note: CachedNote, to dir: URL, filename: String) throws {
        let fileURL = dir.appendingPathComponent(filename)
        try note.text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func makeEntry(note: CachedNote, filename: String) -> ContextEntry {
        return ContextEntry(
            recordName: note.recordName,
            uniqueIdentifier: note.uniqueIdentifier,
            filename: filename,
            title: note.title,
            tags: note.tags,
            recordChangeTag: note.recordChangeTag,
            charCount: note.text.count,
            estimatedTokens: note.text.count / 4,
            lastSyncedAt: Date()
        )
    }

    private func generateIndex(config: ContextConfig, meta: ContextMeta, dir: URL) throws {
        let dateFormatter = ISO8601DateFormatter()
        let bearCount = meta.bearNotes.count
        let externalCount = countFiles(in: dir.appendingPathComponent("external"))
        let inboxCount = countFiles(in: dir.appendingPathComponent("inbox"))
        let totalTokens = meta.bearNotes.values.reduce(0) { $0 + $1.estimatedTokens }
            + tokenEstimateForDir(dir.appendingPathComponent("external"))

        var lines: [String] = []
        lines.append("# Context Library")
        lines.append("")

        var parts: [String] = []
        if bearCount > 0 { parts.append("\(bearCount) from Bear") }
        if externalCount > 0 { parts.append("\(externalCount) external") }
        if inboxCount > 0 { parts.append("\(inboxCount) in inbox") }
        let filesSummary = parts.isEmpty ? "empty" : parts.joined(separator: ", ")

        lines.append("> \(bearCount + externalCount + inboxCount) files | \(filesSummary)")
        if let lastSync = meta.lastSyncDate {
            lines.append("> Last synced: \(dateFormatter.string(from: lastSync)) | ~\(totalTokens) tokens")
        }
        lines.append("")

        // Group Bear notes by subtag
        var groups: [String: [ContextEntry]] = [:]
        for entry in meta.bearNotes.values {
            let group = entry.tags
                .first { $0.hasPrefix(config.tagPrefix) }
                .flatMap { tag in
                    let parts = tag.split(separator: "/", maxSplits: 2)
                    return parts.count > 1 ? String(parts[1]).capitalized : nil
                } ?? "General"
            groups[group, default: []].append(entry)
        }

        for groupName in groups.keys.sorted() {
            let entries = groups[groupName]!.sorted { $0.title < $1.title }
            let groupTokens = entries.reduce(0) { $0 + $1.estimatedTokens }
            lines.append("## \(groupName) (\(entries.count) files, ~\(groupTokens) tokens)")
            lines.append("")
            for entry in entries {
                lines.append("- **bear/\(entry.filename)** — \(entry.title) (~\(entry.estimatedTokens) tokens)")
            }
            lines.append("")
        }

        // External files
        let externalDir = dir.appendingPathComponent("external")
        if let files = try? FileManager.default.contentsOfDirectory(at: externalDir, includingPropertiesForKeys: nil) {
            let mdFiles = files.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            if !mdFiles.isEmpty {
                lines.append("## External (\(mdFiles.count) files)")
                lines.append("")
                for file in mdFiles {
                    let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                    let title = extractTitle(from: content) ?? file.deletingPathExtension().lastPathComponent
                    let tokens = content.count / 4
                    lines.append("- **external/\(file.lastPathComponent)** — \(title) (~\(tokens) tokens)")
                }
                lines.append("")
            }
        }

        // Inbox
        let inboxDir = dir.appendingPathComponent("inbox")
        if let files = try? FileManager.default.contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: nil) {
            let mdFiles = files.filter { $0.pathExtension == "md" }
            lines.append("## Inbox (\(mdFiles.count) files)")
            lines.append("")
            if mdFiles.isEmpty {
                lines.append("_No untriaged files._")
            } else {
                for file in mdFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    lines.append("- **inbox/\(file.lastPathComponent)** — Untriaged")
                }
            }
            lines.append("")
        }

        let indexContent = lines.joined(separator: "\n")
        let indexFile = dir.appendingPathComponent("index.md")
        try indexContent.write(to: indexFile, atomically: true, encoding: .utf8)
    }

    private func countFiles(in dir: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.count
    }

    private func tokenEstimateForDir(_ dir: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.reduce(0) { total, file in
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            return total + size / 4
        }
    }

    private func extractTitle(from text: String) -> String? {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { continue }
            if trimmed.hasPrefix("# ") { return String(trimmed.dropFirst(2)) }
            if !trimmed.isEmpty && !trimmed.hasPrefix("---") { return trimmed }
        }
        return nil
    }

    private func extractSnippet(from content: String, query: String) -> String {
        let lower = content.lowercased()
        guard let range = lower.range(of: query) else { return "" }
        let start = content.index(range.lowerBound, offsetBy: -80, limitedBy: content.startIndex) ?? content.startIndex
        let end = content.index(range.upperBound, offsetBy: 80, limitedBy: content.endIndex) ?? content.endIndex
        var snippet = String(content[start..<end])
        if start != content.startIndex { snippet = "..." + snippet }
        if end != content.endIndex { snippet = snippet + "..." }
        return snippet.replacingOccurrences(of: "\n", with: " ")
    }

    private func findNote(noteID: String) async throws -> CKRecord {
        let records = try await api.lookupRecords(ids: [noteID])
        if let r = records.first { return r }

        let allRecords = try await api.queryAllNotes()
        guard let found = allRecords.first(where: {
            $0.fields["uniqueIdentifier"]?.value.stringValue == noteID
        }) else {
            throw BearCLIError.noteNotFound(noteID)
        }

        let fullRecords = try await api.lookupRecords(ids: [found.recordName])
        guard let full = fullRecords.first else {
            throw BearCLIError.noteNotFound(noteID)
        }
        return full
    }
}

// MARK: - Errors

public enum ContextError: Error, CustomStringConvertible {
    case notInitialized
    case neverSynced

    public var description: String {
        switch self {
        case .notInitialized:
            return "Context library not initialized. Run `bcli context init` first."
        case .neverSynced:
            return "Context library has never been synced. Run `bcli context sync` first."
        }
    }
}
