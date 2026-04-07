import Foundation

// MARK: - Cached Note

public struct CachedNote: Codable {
    public let recordName: String
    public let uniqueIdentifier: String
    public let title: String
    public let tags: [String]
    public let pinned: Bool
    public let archived: Bool
    public let trashed: Bool
    public let locked: Bool
    public let creationDate: Date?
    public let modificationDate: Date?
    public let recordChangeTag: String?
    public let text: String
    public let hasFiles: Bool

    public init(from record: CKRecord, text: String) {
        self.recordName = record.recordName
        self.uniqueIdentifier = record.fields["uniqueIdentifier"]?.value.stringValue ?? record.recordName
        self.title = record.fields["title"]?.value.stringValue ?? "(untitled)"

        if let tagsArray = record.fields["tagsStrings"]?.value.arrayValue {
            self.tags = tagsArray.compactMap { $0.stringValue }
        } else {
            self.tags = []
        }

        self.pinned = record.fields["pinned"]?.value.intValue == 1
        self.archived = record.fields["archived"]?.value.intValue == 1
        self.trashed = record.fields["trashed"]?.value.intValue == 1
        self.locked = record.fields["locked"]?.value.intValue == 1

        if let ts = record.fields["sf_creationDate"]?.value.intValue {
            self.creationDate = Date(timeIntervalSince1970: Double(ts) / 1000.0)
        } else {
            self.creationDate = nil
        }

        if let ts = record.fields["sf_modificationDate"]?.value.intValue {
            self.modificationDate = Date(timeIntervalSince1970: Double(ts) / 1000.0)
        } else {
            self.modificationDate = nil
        }

        self.recordChangeTag = record.recordChangeTag
        self.text = text
        self.hasFiles = record.fields["hasFiles"]?.value.intValue == 1
    }
}

// MARK: - Note Cache

public struct NoteCache: Codable {
    public var syncToken: String?
    public var lastSyncDate: Date?
    public var notes: [String: CachedNote] // keyed by recordName

    public init(syncToken: String? = nil, lastSyncDate: Date? = nil, notes: [String: CachedNote] = [:]) {
        self.syncToken = syncToken
        self.lastSyncDate = lastSyncDate
        self.notes = notes
    }

    public static let staleThresholdSeconds: TimeInterval = 300 // 5 minutes

    public static var cacheFile: URL {
        AuthConfig.configDir.appendingPathComponent("cache.json")
    }

    public static func exists() -> Bool {
        FileManager.default.fileExists(atPath: cacheFile.path)
    }

    public var isStale: Bool {
        guard let lastSync = lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > Self.staleThresholdSeconds
    }

    public static func load() throws -> NoteCache {
        let data = try Data(contentsOf: cacheFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NoteCache.self, from: data)
    }

    public func save() throws {
        let dir = AuthConfig.configDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)

        // Atomic write: write to temp file, then rename
        let tmpFile = dir.appendingPathComponent("cache.json.tmp")
        try data.write(to: tmpFile)
        _ = try FileManager.default.replaceItemAt(Self.cacheFile, withItemAt: tmpFile)
    }

    public mutating func upsert(_ note: CachedNote) {
        notes[note.recordName] = note
    }

    public mutating func remove(recordName: String) {
        notes.removeValue(forKey: recordName)
    }

    /// Upsert from a CKRecord returned after a CLI write operation.
    public mutating func upsertFromRecord(_ record: CKRecord, text: String) {
        let cached = CachedNote(from: record, text: text)
        notes[record.recordName] = cached
    }

    /// Mark a note as trashed in the cache.
    public mutating func markTrashed(recordName: String) {
        guard let existing = notes[recordName] else { return }
        // Re-create with trashed flag - CachedNote is a value type
        let trashed = CachedNote(
            recordName: existing.recordName,
            uniqueIdentifier: existing.uniqueIdentifier,
            title: existing.title,
            tags: existing.tags,
            pinned: existing.pinned,
            archived: existing.archived,
            trashed: true,
            locked: existing.locked,
            creationDate: existing.creationDate,
            modificationDate: existing.modificationDate,
            recordChangeTag: existing.recordChangeTag,
            text: existing.text,
            hasFiles: existing.hasFiles
        )
        notes[recordName] = trashed
    }
}

// MARK: - CachedNote memberwise init (for markTrashed)

extension CachedNote {
    public init(
        recordName: String,
        uniqueIdentifier: String,
        title: String,
        tags: [String],
        pinned: Bool,
        archived: Bool,
        trashed: Bool,
        locked: Bool,
        creationDate: Date?,
        modificationDate: Date?,
        recordChangeTag: String?,
        text: String,
        hasFiles: Bool
    ) {
        self.recordName = recordName
        self.uniqueIdentifier = uniqueIdentifier
        self.title = title
        self.tags = tags
        self.pinned = pinned
        self.archived = archived
        self.trashed = trashed
        self.locked = locked
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.recordChangeTag = recordChangeTag
        self.text = text
        self.hasFiles = hasFiles
    }
}
