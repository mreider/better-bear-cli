import ArgumentParser
import Foundation

struct TrashNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trash",
        abstract: "Move a Bear note to trash"
    )

    @Argument(help: "Note ID (uniqueIdentifier)")
    var noteID: String

    @Flag(name: .long, help: "Skip confirmation prompt")
    var force: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let noteID = self.noteID
        let force = self.force

        try runAsync {
            // Fetch the note
            let records = try await api.lookupRecords(ids: [noteID])
            let record: CKRecord

            if let r = records.first {
                record = r
            } else {
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
                record = full
            }

            let note = BearNote(from: record)

            if !force {
                print("Trash note: \"\(note.title)\"? [y/N] ", terminator: "")
                guard let answer = readLine(), answer.lowercased() == "y" else {
                    print("Cancelled.")
                    return
                }
            }

            let trashed = try await api.trashNote(record: record)
            print("Trashed: \(note.title)")

            // Update local cache
            if NoteCache.exists(), var cache = try? NoteCache.load() {
                cache.markTrashed(recordName: trashed.recordName)
                try? cache.save()
            }
        }
    }
}
