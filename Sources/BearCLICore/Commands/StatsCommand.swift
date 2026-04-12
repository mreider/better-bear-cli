import ArgumentParser
import Foundation

public struct StatsCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Show statistics about your Bear notes library"
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

            var totalNotes = 0
            var pinnedCount = 0
            var taggedCount = 0
            var totalWords = 0
            var tagCounts: [String: Int] = [:]
            var oldest: Date?
            var newest: Date?
            var todoNotes = 0

            for (_, note) in cache.notes {
                if note.trashed { continue }
                totalNotes += 1

                if note.pinned { pinnedCount += 1 }
                if !note.tags.isEmpty { taggedCount += 1 }

                let words = note.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                totalWords += words

                for tag in note.tags {
                    tagCounts[tag, default: 0] += 1
                }

                if let mod = note.modificationDate {
                    if oldest == nil || mod < oldest! { oldest = mod }
                    if newest == nil || mod > newest! { newest = mod }
                }

                if note.text.contains("- [ ]") { todoNotes += 1 }
            }

            let archivedCount = cache.notes.values.filter { !$0.trashed && $0.archived }.count
            let trashedCount = cache.notes.values.filter { $0.trashed }.count
            let uniqueTags = tagCounts.count
            let untaggedCount = totalNotes - taggedCount
            let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(10)

            let dateFormatter = ISO8601DateFormatter()

            if json {
                var output: [String: Any] = [
                    "totalNotes": totalNotes,
                    "pinnedNotes": pinnedCount,
                    "taggedNotes": taggedCount,
                    "untaggedNotes": untaggedCount,
                    "archivedNotes": archivedCount,
                    "trashedNotes": trashedCount,
                    "uniqueTags": uniqueTags,
                    "totalWords": totalWords,
                    "notesWithTodos": todoNotes,
                    "topTags": topTags.map { ["tag": $0.key, "count": $0.value] as [String: Any] },
                ]
                if let d = oldest { output["oldestNote"] = dateFormatter.string(from: d) }
                if let d = newest { output["newestNote"] = dateFormatter.string(from: d) }

                if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"

                print("Notes: \(totalNotes)")
                print("Pinned: \(pinnedCount)")
                print("Tagged: \(taggedCount)")
                print("Untagged: \(untaggedCount)")
                print("Archived: \(archivedCount)")
                print("Trashed: \(trashedCount)")
                print("Tags: \(uniqueTags)")
                print("Words: \(totalWords)")
                print("Notes with TODOs: \(todoNotes)")
                if let d = oldest { print("Oldest: \(df.string(from: d))") }
                if let d = newest { print("Newest: \(df.string(from: d))") }

                if !topTags.isEmpty {
                    print("\nTop tags:")
                    for (tag, count) in topTags {
                        print("  #\(tag): \(count)")
                    }
                }
            }
        }
    }
}
