import ArgumentParser
import Foundation

struct SearchNotes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search Bear notes by title or tag"
    )

    @Argument(help: "Search term")
    var query: String

    @Option(name: .shortAndLong, help: "Maximum results")
    var limit: Int = 20

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let query = self.query
        let limit = self.limit
        let json = self.json

        try runAsync {
            let records = try await api.searchNotes(query: query, limit: limit)
            let notes = Array(records.map { BearNote(from: $0) }.prefix(limit))

            if json {
                var output: [[String: Any]] = []
                for note in notes {
                    output.append([
                        "id": note.uniqueIdentifier,
                        "title": note.title,
                        "tags": note.tags,
                    ])
                }
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                if notes.isEmpty {
                    print("No notes matching '\(query)'")
                    return
                }

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

                for note in notes {
                    let modified = note.modificationDate.map { dateFormatter.string(from: $0) } ?? ""
                    let tags = note.tags.isEmpty ? "" : " [\(note.tags.joined(separator: ", "))]"
                    print("  \(note.uniqueIdentifier)  \(modified)  \(note.title)\(tags)")
                }

                print("\n\(notes.count) results")
            }
        }
    }
}
