import ArgumentParser
import Foundation

struct GetNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Get a Bear note's content"
    )

    @Argument(help: "Note ID (uniqueIdentifier or record name)")
    var noteID: String

    @Flag(name: .long, help: "Output raw markdown without metadata header")
    var raw: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let noteID = self.noteID
        let raw = self.raw
        let json = self.json

        try runAsync {
            // First try direct lookup by record name
            let records = try await api.lookupRecords(ids: [noteID])

            let record: CKRecord
            if let r = records.first {
                record = r
            } else {
                // If not found by record name, search by uniqueIdentifier
                let allRecords = try await api.queryAllNotes(
                    desiredKeys: ["uniqueIdentifier", "title", "text", "tagsStrings", "sf_creationDate", "sf_modificationDate", "pinned"]
                )

                guard let found = allRecords.first(where: {
                    $0.fields["uniqueIdentifier"]?.value.stringValue == noteID
                }) else {
                    throw BearCLIError.noteNotFound(noteID)
                }

                // Re-fetch with all fields
                let fullRecords = try await api.lookupRecords(ids: [found.recordName])
                guard let full = fullRecords.first else {
                    throw BearCLIError.noteNotFound(noteID)
                }
                record = full
            }

            let note = BearNote(from: record)

            // Get note text: prefer textADP (inline string), fall back to text asset
            var noteText = ""
            if let textADP = record.fields["textADP"]?.value.stringValue {
                noteText = textADP
            } else if let assetURL = note.textAssetURL {
                noteText = try await api.downloadAsset(url: assetURL)
            }

            if json {
                let dateFormatter = ISO8601DateFormatter()
                var obj: [String: Any] = [
                    "id": note.uniqueIdentifier,
                    "title": note.title,
                    "tags": note.tags,
                    "pinned": note.pinned,
                    "text": noteText,
                ]
                if let d = note.creationDate { obj["creationDate"] = dateFormatter.string(from: d) }
                if let d = note.modificationDate { obj["modificationDate"] = dateFormatter.string(from: d) }

                if let data = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else if raw {
                print(noteText)
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

                print("Title: \(note.title)")
                print("ID: \(note.uniqueIdentifier)")
                if !note.tags.isEmpty {
                    print("Tags: \(note.tags.joined(separator: ", "))")
                }
                if let d = note.modificationDate {
                    print("Modified: \(dateFormatter.string(from: d))")
                }
                if note.pinned { print("Pinned: yes") }
                print(String(repeating: "─", count: 60))
                print(noteText)
            }
        }
    }
}
