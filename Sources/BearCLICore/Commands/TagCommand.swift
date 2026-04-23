import ArgumentParser
import Foundation

public struct TagCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Manage tags on notes",
        subcommands: [TagAdd.self, TagRemove.self, TagRename.self, TagDelete.self]
    )

    public init() {}
}

// MARK: - Tag Add

struct TagAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a tag to a note"
    )

    @Argument(help: "Note ID (uniqueIdentifier)")
    var noteID: String

    @Argument(help: "Tag to add")
    var tagName: String

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let noteID = self.noteID
        let tagName = self.tagName
        let json = self.json

        try runAsync {
            let record = try await findNoteRecord(api: api, noteID: noteID)

            // Get current note text
            var noteText = ""
            if let textADP = record.fields["textADP"]?.value.stringValue {
                noteText = textADP
            } else if let assetURL = BearNote(from: record).textAssetURL {
                noteText = try await api.downloadAsset(url: assetURL)
            }

            // Check CloudKit's tag index for existence — the authoritative view.
            let currentStrings: [String]
            if let arr = record.fields["tagsStrings"]?.value.arrayValue {
                currentStrings = arr.compactMap { $0.stringValue }
            } else {
                currentStrings = []
            }
            if currentStrings.contains(tagName) {
                if json {
                    let output: [String: Any] = [
                        "id": noteID, "tag": tagName, "added": false, "reason": "already tagged",
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                       let str = String(data: data, encoding: .utf8) { print(str) }
                } else {
                    print("Note already has tag: \(tagName)")
                }
                return
            }

            let tagMarker = tagName.contains(" ") ? "#\(tagName)#" : "#\(tagName)"
            let newText: String

            // Only insert a body marker if the literal token isn't already
            // present. A note may be in the "body has token but index is
            // stale" state (e.g. after hitting the old createNote body-hashtag
            // bug); in that case we still want to (re-)index without doubling
            // the body token.
            let bodyTags = TagParser.extractTags(from: noteText)
            if bodyTags.contains(tagName) {
                newText = noteText
            } else {
                // Add tag after the title line (or first line)
                let lines = noteText.components(separatedBy: "\n")
                var newLines = lines
                // Find the right place — after title and existing tags
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

                // Insert the tag
                if insertIdx < newLines.count && newLines[insertIdx - 1].hasPrefix("#") && !newLines[insertIdx - 1].hasPrefix("# ") {
                    // Append to existing tag line
                    newLines[insertIdx - 1] += " \(tagMarker)"
                } else {
                    newLines.insert(tagMarker, at: insertIdx)
                }

                newText = newLines.joined(separator: "\n")
            }

            // Build updated tag metadata so Bear's tag index reflects the change
            let (tagUUIDs, tagStringValues) = try await buildTagMetadata(
                api: api, record: record, adding: tagName
            )
            let updated = try await api.updateNote(
                record: record, newText: newText,
                tagUUIDs: tagUUIDs, tagStrings: tagStringValues
            )
            let note = BearNote(from: updated)

            if json {
                let output: [String: Any] = [
                    "id": note.uniqueIdentifier, "title": note.title, "tag": tagName, "added": true,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                print("Added tag '\(tagName)' to: \(note.title)")
            }
        }
    }
}

// MARK: - Tag Remove

struct TagRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a tag from a note"
    )

    @Argument(help: "Note ID (uniqueIdentifier)")
    var noteID: String

    @Argument(help: "Tag to remove")
    var tagName: String

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let noteID = self.noteID
        let tagName = self.tagName
        let json = self.json

        try runAsync {
            let record = try await findNoteRecord(api: api, noteID: noteID)

            var noteText = ""
            if let textADP = record.fields["textADP"]?.value.stringValue {
                noteText = textADP
            } else if let assetURL = BearNote(from: record).textAssetURL {
                noteText = try await api.downloadAsset(url: assetURL)
            }

            // Check existence in the CloudKit index, not the body markdown.
            // Ancestor tags may be indexed without a literal body token.
            let currentStrings: [String]
            if let arr = record.fields["tagsStrings"]?.value.arrayValue {
                currentStrings = arr.compactMap { $0.stringValue }
            } else {
                currentStrings = []
            }

            guard currentStrings.contains(tagName) else {
                if json {
                    let output: [String: Any] = [
                        "id": noteID, "tag": tagName, "removed": false, "reason": "tag not found",
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                       let str = String(data: data, encoding: .utf8) { print(str) }
                } else {
                    print("Tag '\(tagName)' not found in note")
                }
                return
            }

            // Strip the tag marker from the body only where it appears as a
            // real token. For an ancestor tag whose only descendant is still
            // present (e.g. removing `parent` while `#parent/child` remains),
            // the body won't contain a literal `#parent` and stays untouched.
            let newText = TagParser.stripTag(from: noteText, name: tagName)

            // Build updated tag metadata so Bear's tag index reflects the removal
            let (tagUUIDs, tagStringValues) = try await buildTagMetadata(
                api: api, record: record, removing: tagName
            )
            let updated = try await api.updateNote(
                record: record, newText: newText,
                tagUUIDs: tagUUIDs, tagStrings: tagStringValues
            )
            let note = BearNote(from: updated)

            if json {
                let output: [String: Any] = [
                    "id": note.uniqueIdentifier, "title": note.title, "tag": tagName, "removed": true,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                print("Removed tag '\(tagName)' from: \(note.title)")
            }
        }
    }
}

// MARK: - Tag Rename

struct TagRename: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a tag across all notes"
    )

    @Argument(help: "Current tag name")
    var oldName: String

    @Argument(help: "New tag name")
    var newName: String

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let oldName = self.oldName
        let newName = self.newName
        let json = self.json

        try runAsync {
            let engine = SyncEngine(api: api)
            let cache = try await engine.ensureCacheReady()

            var updatedCount = 0

            for (_, note) in cache.notes {
                if note.trashed { continue }
                // Pre-filter on the indexed tag strings. This is faster than a
                // full-body scan and also catches notes whose CloudKit index
                // holds `oldName` via ancestor expansion even though the body
                // never spells it out literally (e.g. body has `#foo/bar` but
                // the index includes `foo`).
                if !note.tags.contains(oldName) { continue }

                let record = try await api.lookupRecords(ids: [note.recordName]).first
                guard let record = record else { continue }

                // Boundary-aware rename in the body. `TagParser.renameTagPrefix`
                // refuses to match across tag boundaries, so renaming `context`
                // won't mangle `#contexts` or the unrelated `#context-y`.
                let newText = TagParser.renameTagPrefix(
                    in: note.text, from: oldName, to: newName
                )

                // Update the CloudKit tag index so Bear's sidebar reflects the
                // rename immediately — previously the body was rewritten but
                // `tagsStrings` / `tags` were stale until Bear re-parsed.
                let (tagUUIDs, tagStringValues) = try await buildTagMetadata(
                    api: api, record: record, adding: newName, removing: oldName
                )
                _ = try await api.updateNote(
                    record: record, newText: newText,
                    tagUUIDs: tagUUIDs, tagStrings: tagStringValues
                )
                updatedCount += 1
            }

            if json {
                let output: [String: Any] = [
                    "oldTag": oldName, "newTag": newName, "notesUpdated": updatedCount,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                print("Renamed '\(oldName)' → '\(newName)' in \(updatedCount) notes")
            }
        }
    }
}

// MARK: - Tag Delete

struct TagDelete: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Remove a tag from all notes"
    )

    @Argument(help: "Tag to delete")
    var tagName: String

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let tagName = self.tagName
        let json = self.json

        try runAsync {
            let engine = SyncEngine(api: api)
            let cache = try await engine.ensureCacheReady()

            var updatedCount = 0

            for (_, note) in cache.notes {
                if note.trashed { continue }
                // Pre-filter on the indexed tag strings. This visits notes
                // whose CloudKit index contains `tagName` even when the body
                // has no literal `#tagName` token — that's the phantom-ancestor
                // case (body has `#foo/bar`, index also carries `foo`).
                if !note.tags.contains(tagName) { continue }

                let record = try await api.lookupRecords(ids: [note.recordName]).first
                guard let record = record else { continue }

                // Boundary-aware body strip. `TagParser.stripTag` refuses to
                // truncate `#foo/bar` when removing `foo`.
                let newText = TagParser.stripTag(from: note.text, name: tagName)

                // Update the CloudKit tag index so Bear's sidebar reflects
                // the removal — previously the body was rewritten but
                // `tagsStrings` / `tags` were stale until Bear re-parsed.
                let (tagUUIDs, tagStringValues) = try await buildTagMetadata(
                    api: api, record: record, removing: tagName
                )
                _ = try await api.updateNote(
                    record: record, newText: newText,
                    tagUUIDs: tagUUIDs, tagStrings: tagStringValues
                )
                updatedCount += 1
            }

            // Finally, delete the SFNoteTag record itself so the tag no longer
            // appears in `bear_get_tags` or Bear's sidebar. Without this step
            // the tag record persists as a phantom with a stale `notesCount`.
            var tagRecordDeleted = false
            if let tagRecord = try await api.findTagRecord(byName: tagName) {
                try await api.deleteRecord(recordName: tagRecord.recordName)
                tagRecordDeleted = true
            }

            if json {
                let output: [String: Any] = [
                    "tag": tagName,
                    "notesUpdated": updatedCount,
                    "deleted": tagRecordDeleted,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                let deletedNote = tagRecordDeleted ? "" : " (tag record not found)"
                print("Deleted tag '\(tagName)' from \(updatedCount) notes\(deletedNote)")
            }
        }
    }
}

// MARK: - Shared helpers

/// Build the updated `tags` (UUID list) and `tagsStrings` (string list) for a
/// note after adding or removing a tag. Matches Bear desktop's index behaviour:
/// adding a hierarchical tag also indexes every ancestor; removing a tag drops
/// any ancestor that no longer has a descendant in the note's index.
private func buildTagMetadata(
    api: CloudKitAPI,
    record: CKRecord,
    adding: String? = nil,
    removing: String? = nil
) async throws -> (tagUUIDs: [String], tagStrings: [String]) {
    var currentStrings: [String] = []
    if let arr = record.fields["tagsStrings"]?.value.arrayValue {
        currentStrings = arr.compactMap { $0.stringValue }
    }

    if let add = adding {
        for t in TagParser.expandAncestors([add]) where !currentStrings.contains(t) {
            currentStrings.append(t)
        }
    }

    if let remove = removing {
        currentStrings = TagParser.remainingTagsAfterRemoval(
            from: currentStrings, removing: remove
        )
    }

    let nameToUUID = try await api.ensureTagsExist(names: currentStrings)
    let uuids = currentStrings.compactMap { nameToUUID[$0] }
    return (uuids, currentStrings)
}

private func findNoteRecord(api: CloudKitAPI, noteID: String) async throws -> CKRecord {
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
