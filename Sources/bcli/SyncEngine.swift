import Foundation

struct SyncStats {
    var added: Int = 0
    var updated: Int = 0
    var deleted: Int = 0
    var failed: Int = 0

    var total: Int { added + updated + deleted }

    var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) new") }
        if updated > 0 { parts.append("\(updated) updated") }
        if deleted > 0 { parts.append("\(deleted) deleted") }
        if failed > 0 { parts.append("\(failed) failed") }
        if parts.isEmpty { return "no changes" }
        return parts.joined(separator: ", ")
    }
}

struct SyncEngine {
    let api: CloudKitAPI

    /// Main sync entry point.
    func sync(force: Bool = false, verbose: Bool = false) async throws -> (NoteCache, SyncStats) {
        if force || !NoteCache.exists() {
            return try await performFullSync(verbose: verbose)
        }

        do {
            var cache = try NoteCache.load()
            if cache.syncToken == nil {
                return try await performFullSync(verbose: verbose)
            }
            let stats = try await performIncrementalSync(cache: &cache, verbose: verbose)
            return (cache, stats)
        } catch let error as BearCLIError {
            // If the API returns an error (possibly stale token), fall back to full sync
            if case .apiError = error {
                if verbose { print("Sync token rejected, performing full re-sync...") }
                return try await performFullSync(verbose: verbose)
            }
            throw error
        }
    }

    /// Ensure cache exists and is reasonably fresh. Used by search before querying.
    func ensureCacheReady(verbose: Bool = false) async throws -> NoteCache {
        if !NoteCache.exists() {
            if verbose { print("No local cache found. Syncing...") }
            let (cache, stats) = try await performFullSync(verbose: verbose)
            if verbose { print("Synced \(cache.notes.count) notes (\(stats.summary))") }
            return cache
        }

        var cache = try NoteCache.load()
        if cache.isStale {
            if verbose { print("Cache is stale. Syncing...") }
            if cache.syncToken != nil {
                let stats = try await performIncrementalSync(cache: &cache, verbose: verbose)
                if verbose { print("Sync complete (\(stats.summary))") }
            } else {
                let (newCache, stats) = try await performFullSync(verbose: verbose)
                if verbose { print("Synced \(newCache.notes.count) notes (\(stats.summary))") }
                return newCache
            }
        }
        return cache
    }

    // MARK: - Full Sync

    private func performFullSync(verbose: Bool) async throws -> (NoteCache, SyncStats) {
        // Get the current syncToken from zones/list
        let zones = try await api.listZones()
        let syncToken = zones.first(where: { $0.zoneID.zoneName == "Notes" })?.syncToken

        if verbose { print("Fetching all notes...") }

        // Fetch all notes with text content
        let records = try await api.queryAllNotes(
            desiredKeys: [
                "uniqueIdentifier", "title", "text", "textADP",
                "tagsStrings", "sf_creationDate", "sf_modificationDate",
                "pinned", "archived", "trashed", "locked",
                "hasFiles",
            ]
        )

        if verbose { print("Downloaded index: \(records.count) notes. Fetching text content...") }

        var cache = NoteCache(syncToken: syncToken, lastSyncDate: Date(), notes: [:])
        var stats = SyncStats()
        var count = 0

        for record in records {
            let text: String
            do {
                text = try await fetchNoteText(from: record)
            } catch {
                stats.failed += 1
                if verbose { print("  Failed to fetch text for \(record.recordName): \(error)") }
                continue
            }

            let cached = CachedNote(from: record, text: text)
            cache.notes[record.recordName] = cached
            stats.added += 1
            count += 1

            if verbose && count % 25 == 0 {
                print("  \(count)/\(records.count)...")
            }
        }

        try cache.save()
        return (cache, stats)
    }

    // MARK: - Incremental Sync

    private func performIncrementalSync(cache: inout NoteCache, verbose: Bool) async throws -> SyncStats {
        var stats = SyncStats()
        var currentToken = cache.syncToken

        repeat {
            let result = try await api.fetchZoneChanges(syncToken: currentToken)

            for record in result.records {
                if record.deleted == true {
                    if cache.notes.removeValue(forKey: record.recordName) != nil {
                        stats.deleted += 1
                    }
                    continue
                }

                // Only process SFNote records (skip tags, images, etc.)
                guard record.recordType == "SFNote" || record.recordType == nil else {
                    continue
                }

                let isNew = cache.notes[record.recordName] == nil

                let text: String
                do {
                    text = try await fetchNoteText(from: record)
                } catch {
                    stats.failed += 1
                    if verbose { print("  Failed to fetch text for \(record.recordName): \(error)") }
                    continue
                }

                let cached = CachedNote(from: record, text: text)
                cache.notes[record.recordName] = cached

                if isNew {
                    stats.added += 1
                } else {
                    stats.updated += 1
                }

                if verbose {
                    let action = isNew ? "+" : "~"
                    print("  \(action) \(cached.title)")
                }
            }

            currentToken = result.syncToken

            if result.moreComing && verbose {
                print("  Fetching more changes...")
            }

            if !result.moreComing { break }
        } while true

        cache.syncToken = currentToken
        cache.lastSyncDate = Date()
        try cache.save()
        return stats
    }

    // MARK: - Shared Text Fetching

    /// Get note text from a CKRecord - tries textADP (inline) first, then asset download.
    func fetchNoteText(from record: CKRecord) async throws -> String {
        if let textADP = record.fields["textADP"]?.value.stringValue {
            return textADP
        }

        if let textDict = record.fields["text"]?.value.dictValue,
           let downloadURL = textDict["downloadURL"]?.stringValue {
            return try await api.downloadAsset(url: downloadURL)
        }

        return ""
    }
}
