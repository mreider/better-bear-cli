import ArgumentParser
import Foundation

struct ListNotes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List Bear notes"
    )

    @Option(name: .shortAndLong, help: "Maximum number of notes to show")
    var limit: Int = 30

    @Flag(name: .long, help: "Show archived notes")
    var archived: Bool = false

    @Flag(name: .long, help: "Show trashed notes")
    var trashed: Bool = false

    @Flag(name: .long, help: "Show all notes (fetch beyond limit)")
    var all: Bool = false

    @Option(name: .shortAndLong, help: "Filter by tag (partial match)")
    var tag: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let all = self.all
        let trashed = self.trashed
        let archived = self.archived
        let limit = self.limit
        let tag = self.tag
        let json = self.json

        try runAsync {
            let records: [CKRecord]
            if all {
                records = try await api.queryAllNotes(
                    trashed: trashed,
                    archived: archived,
                    desiredKeys: ["uniqueIdentifier", "title", "sf_creationDate", "sf_modificationDate", "tagsStrings", "pinned", "todoCompleted", "todoIncompleted"]
                )
            } else {
                records = try await api.queryNotes(
                    trashed: trashed,
                    archived: archived,
                    limit: limit,
                    desiredKeys: ["uniqueIdentifier", "title", "sf_creationDate", "sf_modificationDate", "tagsStrings", "pinned", "todoCompleted", "todoIncompleted"]
                )
            }

            var notes = records.map { BearNote(from: $0) }

            if let tagFilter = tag?.lowercased() {
                notes = notes.filter { note in
                    note.tags.contains { $0.lowercased().contains(tagFilter) }
                }
            }

            if json {
                printJSON(notes)
            } else {
                printTable(notes)
            }
        }
    }

    private func printTable(_ notes: [BearNote]) {
        if notes.isEmpty {
            print("No notes found.")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        print("ID".padding(toLength: 38, withPad: " ", startingAt: 0) + "  " +
              "Modified".padding(toLength: 16, withPad: " ", startingAt: 0) + "  " + "Title")
        print(String(repeating: "─", count: 90))

        for note in notes {
            let modified = note.modificationDate.map { dateFormatter.string(from: $0) } ?? "unknown"
            let pin = note.pinned ? "* " : ""
            let tags = note.tags.isEmpty ? "" : " [\(note.tags.joined(separator: ", "))]"
            let title = "\(pin)\(note.title)\(tags)"
            print(note.uniqueIdentifier.padding(toLength: 38, withPad: " ", startingAt: 0) + "  " +
                  modified.padding(toLength: 16, withPad: " ", startingAt: 0) + "  " + title)
        }

        print("\n\(notes.count) notes")
    }

    private func printJSON(_ notes: [BearNote]) {
        var output: [[String: Any]] = []
        for note in notes {
            output.append([
                "id": note.uniqueIdentifier,
                "title": note.title,
                "tags": note.tags,
                "pinned": note.pinned,
                "modificationDate": note.modificationDate?.timeIntervalSince1970 ?? 0,
            ])
        }
        if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}
