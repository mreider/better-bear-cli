import ArgumentParser
import Foundation

public struct HealthCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "health",
        abstract: "Report on the health of your Bear notes library"
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

            let now = Date()
            let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 60 * 60)

            var totalNotes = 0
            var emptyNotes: [[String: String]] = []
            var untaggedCount = 0
            var conflicted: [[String: String]] = []
            var trashedOld: [[String: String]] = []
            var largeNotes: [[String: String]] = []
            var titleCounts: [String: [(id: String, mod: Date?)]] = [:]
            var tagNoteCounts: [String: Int] = [:]

            for (_, note) in cache.notes {
                // Skip trashed for most checks
                let isTrashed = note.trashed

                if !isTrashed {
                    totalNotes += 1

                    // Empty/untitled
                    let bodyEmpty = note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || note.text.trimmingCharacters(in: .whitespacesAndNewlines) == "# "
                        || note.text.trimmingCharacters(in: .whitespacesAndNewlines) == "# \(note.title)"
                    if note.title.trimmingCharacters(in: .whitespaces).isEmpty || bodyEmpty {
                        emptyNotes.append(["id": note.uniqueIdentifier, "title": note.title.isEmpty ? "(untitled)" : note.title])
                    }

                    // Untagged
                    if note.tags.isEmpty { untaggedCount += 1 }

                    // Duplicate titles
                    if !note.title.isEmpty {
                        titleCounts[note.title, default: []].append((note.uniqueIdentifier, note.modificationDate))
                    }

                    // Tags
                    for tag in note.tags {
                        tagNoteCounts[tag, default: 0] += 1
                    }

                    // Conflicted
                    // Notes with conflictUniqueIdentifier set indicate sync conflicts
                    // We check the text for conflict markers
                    if note.title.contains("conflict") || note.title.contains("Conflict") {
                        conflicted.append(["id": note.uniqueIdentifier, "title": note.title])
                    }

                    // Large notes (over 50KB of text)
                    if note.text.utf8.count > 50_000 {
                        let sizeKB = note.text.utf8.count / 1024
                        largeNotes.append(["id": note.uniqueIdentifier, "title": note.title, "size": "\(sizeKB)KB"])
                    }
                }

                // Trashed notes older than 30 days
                if isTrashed, let mod = note.modificationDate, mod < thirtyDaysAgo {
                    trashedOld.append(["id": note.uniqueIdentifier, "title": note.title])
                }
            }

            // Find duplicates
            let duplicates = titleCounts.filter { $0.value.count > 1 }
            var duplicateList: [[String: String]] = []
            for (title, entries) in duplicates.sorted(by: { $0.key < $1.key }) {
                for entry in entries {
                    duplicateList.append(["id": entry.id, "title": title])
                }
            }

            // Find orphaned tags from the tag tree
            let allTags = try await api.queryTags()
            var orphanedTags: [String] = []
            for tagRecord in allTags {
                let tagTitle = tagRecord.fields["title"]?.value.stringValue ?? ""
                let count = Int(tagRecord.fields["notesCount"]?.value.intValue ?? 0)
                if count == 0 && !tagTitle.isEmpty {
                    orphanedTags.append(tagTitle)
                }
            }

            if json {
                var output: [String: Any] = [
                    "totalNotes": totalNotes,
                    "totalTags": tagNoteCounts.count,
                    "duplicateTitles": duplicates.count,
                    "duplicates": duplicateList.map { $0 as [String: Any] },
                    "emptyNotes": emptyNotes.count,
                    "emptyList": emptyNotes.map { $0 as [String: Any] },
                    "untaggedNotes": untaggedCount,
                    "trashedOver30Days": trashedOld.count,
                    "trashedList": trashedOld.map { $0 as [String: Any] },
                    "conflictedNotes": conflicted.count,
                    "conflictedList": conflicted.map { $0 as [String: Any] },
                    "orphanedTags": orphanedTags.count,
                    "orphanedTagsList": orphanedTags,
                    "largeNotes": largeNotes.count,
                    "largeList": largeNotes.map { $0 as [String: Any] },
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print("=== Bear Health Report ===\n")

                func report(_ icon: String, _ count: Int, _ label: String, _ items: [[String: String]]? = nil) {
                    if count > 0 {
                        print("\(icon)  \(count) \(label)")
                        if let items = items {
                            for item in items.prefix(10) {
                                print("    \(item["id"] ?? "")  \(item["title"] ?? "")")
                            }
                            if items.count > 10 {
                                print("    ... and \(items.count - 10) more")
                            }
                        }
                    } else {
                        print("✓  No \(label)")
                    }
                }

                report("⚠", duplicates.count, "duplicate titles (\(duplicateList.count) total notes)")
                report("⚠", emptyNotes.count, "empty/untitled notes", emptyNotes)
                report("⚠", trashedOld.count, "notes in trash for 30+ days")
                report("⚠", conflicted.count, "conflicted notes (sync conflicts)", conflicted)
                report("ℹ", untaggedCount, "untagged notes")
                report("ℹ", orphanedTags.count, "orphaned tags (0 notes)", orphanedTags.map { ["id": "", "title": $0] })
                report("ℹ", largeNotes.count, "notes over 50KB", largeNotes)

                print("\n\(totalNotes) notes, \(tagNoteCounts.count) tags")

                let warnings = [duplicates.count, emptyNotes.count, trashedOld.count, conflicted.count].filter { $0 > 0 }.count
                if warnings == 0 { print("Everything looks good!") }
            }
        }
    }
}
