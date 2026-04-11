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

            // Check if tag already exists in the note
            let tagMarker = tagName.contains(" ") ? "#\(tagName)#" : "#\(tagName)"
            if noteText.contains(tagMarker) {
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

            let newText = newLines.joined(separator: "\n")
            let updated = try await api.updateNote(record: record, newText: newText)
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

            // Remove the tag (both #tag and #tag with spaces#)
            let tagHash = tagName.contains(" ") ? "#\(tagName)#" : "#\(tagName)"
            var newText = noteText

            // Remove standalone tag line
            let lines = newText.components(separatedBy: "\n")
            var newLines: [String] = []
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == tagHash {
                    continue // remove entire line
                }
                // Remove tag from a line with multiple tags
                var modified = line.replacingOccurrences(of: " \(tagHash)", with: "")
                modified = modified.replacingOccurrences(of: "\(tagHash) ", with: "")
                modified = modified.replacingOccurrences(of: tagHash, with: "")
                newLines.append(modified)
            }
            newText = newLines.joined(separator: "\n")

            if newText == noteText {
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

            let updated = try await api.updateNote(record: record, newText: newText)
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

            let oldHash = oldName.contains(" ") ? "#\(oldName)#" : "#\(oldName)"
            let newHash = newName.contains(" ") ? "#\(newName)#" : "#\(newName)"

            var updatedCount = 0

            for (_, note) in cache.notes {
                if note.trashed { continue }
                if !note.text.contains(oldHash) { continue }

                let record = try await api.lookupRecords(ids: [note.recordName]).first
                guard let record = record else { continue }

                let newText = note.text.replacingOccurrences(of: oldHash, with: newHash)
                _ = try await api.updateNote(record: record, newText: newText)
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

            let tagHash = tagName.contains(" ") ? "#\(tagName)#" : "#\(tagName)"
            var updatedCount = 0

            for (_, note) in cache.notes {
                if note.trashed { continue }
                if !note.text.contains(tagHash) { continue }

                let record = try await api.lookupRecords(ids: [note.recordName]).first
                guard let record = record else { continue }

                // Remove the tag from the text
                let lines = note.text.components(separatedBy: "\n")
                var newLines: [String] = []
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed == tagHash { continue }
                    var modified = line.replacingOccurrences(of: " \(tagHash)", with: "")
                    modified = modified.replacingOccurrences(of: "\(tagHash) ", with: "")
                    modified = modified.replacingOccurrences(of: tagHash, with: "")
                    newLines.append(modified)
                }
                let newText = newLines.joined(separator: "\n")

                if newText != note.text {
                    _ = try await api.updateNote(record: record, newText: newText)
                    updatedCount += 1
                }
            }

            if json {
                let output: [String: Any] = [
                    "tag": tagName, "notesUpdated": updatedCount, "deleted": true,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                print("Deleted tag '\(tagName)' from \(updatedCount) notes")
            }
        }
    }
}

// MARK: - Shared helper

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
