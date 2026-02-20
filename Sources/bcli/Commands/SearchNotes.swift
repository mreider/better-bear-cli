import ArgumentParser
import Foundation

struct SearchNotes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search Bear notes (full-text)"
    )

    @Argument(help: "Search term")
    var query: String

    @Option(name: .shortAndLong, help: "Maximum results")
    var limit: Int = 20

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Flag(name: .long, help: "Skip auto-sync (use existing cache as-is)")
    var noSync: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let query = self.query
        let limit = self.limit
        let json = self.json
        let noSync = self.noSync

        try runAsync {
            // Load or sync cache
            let cache: NoteCache
            if noSync {
                guard NoteCache.exists() else {
                    print("No local cache. Run `bcli sync` first, or remove --no-sync.")
                    return
                }
                cache = try NoteCache.load()
            } else {
                let engine = SyncEngine(api: api)
                cache = try await engine.ensureCacheReady()
            }

            let term = query.lowercased()

            // Score and rank results
            struct SearchResult {
                let note: CachedNote
                let matchType: MatchType
                let snippet: String?
            }

            enum MatchType: Int, Comparable {
                case title = 0
                case tag = 1
                case body = 2

                static func < (lhs: MatchType, rhs: MatchType) -> Bool {
                    lhs.rawValue < rhs.rawValue
                }
            }

            var results: [SearchResult] = []

            for (_, note) in cache.notes {
                // Skip trashed notes
                if note.trashed { continue }

                let titleMatch = note.title.lowercased().contains(term)
                let tagMatch = note.tags.contains { $0.lowercased().contains(term) }
                let bodyMatch = note.text.lowercased().contains(term)

                if !titleMatch && !tagMatch && !bodyMatch { continue }

                let matchType: MatchType
                if titleMatch {
                    matchType = .title
                } else if tagMatch {
                    matchType = .tag
                } else {
                    matchType = .body
                }

                let snippet: String?
                if bodyMatch && !titleMatch {
                    snippet = extractSnippet(from: note.text, matching: term)
                } else {
                    snippet = nil
                }

                results.append(SearchResult(note: note, matchType: matchType, snippet: snippet))
            }

            // Sort: by match type (title first), then by modification date
            results.sort { a, b in
                if a.matchType != b.matchType { return a.matchType < b.matchType }
                let aDate = a.note.modificationDate ?? .distantPast
                let bDate = b.note.modificationDate ?? .distantPast
                return aDate > bDate
            }

            let limited = Array(results.prefix(limit))

            if json {
                var output: [[String: Any]] = []
                for result in limited {
                    var entry: [String: Any] = [
                        "id": result.note.uniqueIdentifier,
                        "title": result.note.title,
                        "tags": result.note.tags,
                        "match": "\(result.matchType)",
                    ]
                    if let snippet = result.snippet {
                        entry["snippet"] = snippet
                    }
                    output.append(entry)
                }
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                if limited.isEmpty {
                    print("No notes matching '\(query)'")
                    return
                }

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

                for result in limited {
                    let note = result.note
                    let modified = note.modificationDate.map { dateFormatter.string(from: $0) } ?? ""
                    let tags = note.tags.isEmpty ? "" : " [\(note.tags.joined(separator: ", "))]"
                    print("  \(note.uniqueIdentifier)  \(modified)  \(note.title)\(tags)")

                    if let snippet = result.snippet {
                        print("    ...\(snippet)...")
                    }
                }

                print("\n\(limited.count) results")
            }
        }
    }

    /// Extract a context snippet around the first match in the text.
    private func extractSnippet(from text: String, matching term: String) -> String {
        let lower = text.lowercased()
        guard let range = lower.range(of: term) else { return "" }

        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let snippetStart = max(0, matchStart - 40)
        let snippetEnd = min(text.count, matchStart + term.count + 40)

        let startIdx = text.index(text.startIndex, offsetBy: snippetStart)
        let endIdx = text.index(text.startIndex, offsetBy: snippetEnd)
        var snippet = String(text[startIdx..<endIdx])

        // Clean up: replace newlines with spaces, trim
        snippet = snippet.replacingOccurrences(of: "\n", with: " ")
        snippet = snippet.trimmingCharacters(in: .whitespaces)

        return snippet
    }
}
