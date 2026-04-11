import ArgumentParser
import Foundation

public struct ArchiveNote: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Archive or unarchive a Bear note"
    )

    @Argument(help: "Note ID (uniqueIdentifier)")
    var noteID: String

    @Flag(name: .long, help: "Unarchive the note")
    var undo: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    public init() {}

    public func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let noteID = self.noteID
        let undoArchive = self.undo
        let json = self.json

        try runAsync {
            let record = try await findNote(api: api, noteID: noteID)
            let note = BearNote(from: record)

            let updated = try await api.archiveNote(record: record, archive: !undoArchive)

            if json {
                let output: [String: Any] = [
                    "id": note.uniqueIdentifier,
                    "title": note.title,
                    "archived": !undoArchive,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print(undoArchive ? "Unarchived: \(note.title)" : "Archived: \(note.title)")
            }

            if NoteCache.exists(), var cache = try? NoteCache.load() {
                cache.upsertFromRecord(updated, text: "")
                try? cache.save()
            }
        }
    }

    private func findNote(api: CloudKitAPI, noteID: String) async throws -> CKRecord {
        let records = try await api.lookupRecords(ids: [noteID])
        if let r = records.first { return r }

        let allRecords = try await api.queryAllNotes(archived: true)
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
