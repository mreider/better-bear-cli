import ArgumentParser
import Foundation

public struct DuplicatesCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "duplicates",
        abstract: "Find notes with duplicate titles"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    public init() {}

    public func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let json = self.json

        try runAsync {
            let engine = SyncEngine(api: api)
            let cache = try await engine.ensureCacheReady()

            var titleGroups: [String: [(id: String, modified: Date?)]] = [:]

            for (_, note) in cache.notes {
                if note.trashed { continue }
                let title = note.title.trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                titleGroups[title, default: []].append((note.uniqueIdentifier, note.modificationDate))
            }

            let duplicates = titleGroups.filter { $0.value.count > 1 }

            if json {
                var groups: [[String: Any]] = []
                for (title, entries) in duplicates.sorted(by: { $0.key < $1.key }) {
                    let dateFormatter = ISO8601DateFormatter()
                    let notes = entries.map { entry -> [String: Any] in
                        var d: [String: Any] = ["id": entry.id]
                        if let mod = entry.modified {
                            d["modified"] = dateFormatter.string(from: mod)
                        }
                        return d
                    }
                    groups.append(["title": title, "count": entries.count, "notes": notes])
                }

                let output: [String: Any] = [
                    "duplicateGroups": groups.count,
                    "totalDuplicateNotes": duplicates.values.map(\.count).reduce(0, +),
                    "groups": groups,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                if duplicates.isEmpty {
                    print("No duplicate titles found.")
                    return
                }

                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd HH:mm"

                print("Found \(duplicates.count) duplicate titles:\n")
                for (title, entries) in duplicates.sorted(by: { $0.key < $1.key }) {
                    print("  \"\(title)\" (\(entries.count) copies)")
                    for entry in entries.sorted(by: { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }) {
                        let mod = entry.modified.map { df.string(from: $0) } ?? "unknown"
                        print("    \(entry.id)  \(mod)")
                    }
                }
            }
        }
    }
}
