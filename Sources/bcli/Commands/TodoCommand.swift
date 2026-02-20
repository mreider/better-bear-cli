import ArgumentParser
import Foundation

struct TodoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "todo",
        abstract: "List and toggle TODO items in Bear notes"
    )

    @Argument(help: "Note ID to view/toggle TODOs (omit to list all notes with TODOs)")
    var noteID: String?

    @Option(name: .shortAndLong, help: "Toggle TODO item by number (non-interactive)")
    var toggle: Int?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Flag(name: .long, help: "Skip auto-sync (use existing cache as-is)")
    var noSync: Bool = false

    @Option(name: .shortAndLong, help: "Maximum notes to show in list mode")
    var limit: Int = 30

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let noteID = self.noteID
        let toggleIndex = self.toggle
        let json = self.json
        let noSync = self.noSync
        let limit = self.limit

        try runAsync {
            if let noteID = noteID {
                try await handleToggleMode(api: api, noteID: noteID, toggleIndex: toggleIndex, json: json)
            } else {
                try await handleListMode(api: api, json: json, noSync: noSync, limit: limit)
            }
        }
    }

    // MARK: - List mode

    private func handleListMode(api: CloudKitAPI, json: Bool, noSync: Bool, limit: Int) async throws {
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

        struct TodoSummary {
            let note: CachedNote
            let incomplete: Int
            let complete: Int
        }

        var results: [TodoSummary] = []

        for (_, note) in cache.notes {
            if note.trashed { continue }

            let incomplete = countOccurrences(of: "- [ ]", in: note.text)
            let complete = countOccurrences(of: "- [x]", in: note.text)

            if incomplete > 0 {
                results.append(TodoSummary(note: note, incomplete: incomplete, complete: complete))
            }
        }

        results.sort { a, b in
            if a.incomplete != b.incomplete { return a.incomplete > b.incomplete }
            let aDate = a.note.modificationDate ?? .distantPast
            let bDate = b.note.modificationDate ?? .distantPast
            return aDate > bDate
        }

        let limited = Array(results.prefix(limit))

        if json {
            var output: [[String: Any]] = []
            for result in limited {
                output.append([
                    "id": result.note.uniqueIdentifier,
                    "title": result.note.title,
                    "tags": result.note.tags,
                    "todoIncomplete": result.incomplete,
                    "todoComplete": result.complete,
                ])
            }
            if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            if limited.isEmpty {
                print("No notes with incomplete TODOs.")
                return
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

            print("ID".padding(toLength: 38, withPad: " ", startingAt: 0) + "  " +
                  "TODOs".padding(toLength: 10, withPad: " ", startingAt: 0) + "  " + "Title")
            print(String(repeating: "-", count: 90))

            for result in limited {
                let note = result.note
                let todoStr = "\(result.incomplete) left"
                let tags = note.tags.isEmpty ? "" : " [\(note.tags.joined(separator: ", "))]"
                print(note.uniqueIdentifier.padding(toLength: 38, withPad: " ", startingAt: 0) + "  " +
                      todoStr.padding(toLength: 10, withPad: " ", startingAt: 0) + "  " +
                      "\(note.title)\(tags)")
            }

            print("\n\(limited.count) notes with incomplete TODOs")
        }
    }

    // MARK: - Toggle mode

    private func handleToggleMode(api: CloudKitAPI, noteID: String, toggleIndex: Int?, json: Bool) async throws {
        let record = try await findNoteRecord(api: api, noteID: noteID)

        let currentText: String
        if let textADP = record.fields["textADP"]?.value.stringValue {
            currentText = textADP
        } else if let assetURL = BearNote(from: record).textAssetURL {
            currentText = try await api.downloadAsset(url: assetURL)
        } else {
            currentText = ""
        }

        let lines = currentText.components(separatedBy: "\n")

        struct TodoItem {
            let lineIndex: Int
            let text: String
            let isComplete: Bool
            let indent: Int
        }

        var todos: [TodoItem] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count

            if trimmed.hasPrefix("- [ ] ") {
                todos.append(TodoItem(lineIndex: i, text: String(trimmed.dropFirst(6)), isComplete: false, indent: indent))
            } else if trimmed == "- [ ]" {
                todos.append(TodoItem(lineIndex: i, text: "", isComplete: false, indent: indent))
            } else if trimmed.hasPrefix("- [x] ") {
                todos.append(TodoItem(lineIndex: i, text: String(trimmed.dropFirst(6)), isComplete: true, indent: indent))
            } else if trimmed == "- [x]" {
                todos.append(TodoItem(lineIndex: i, text: "", isComplete: true, indent: indent))
            }
        }

        if todos.isEmpty {
            print("No TODO items found in this note.")
            return
        }

        let note = BearNote(from: record)

        // JSON output without toggle - just list the TODOs
        if json && toggleIndex == nil {
            var output: [[String: Any]] = []
            for (i, todo) in todos.enumerated() {
                output.append([
                    "index": i + 1,
                    "text": todo.text,
                    "complete": todo.isComplete,
                ])
            }
            let wrapper: [String: Any] = [
                "id": note.uniqueIdentifier,
                "title": note.title,
                "todos": output,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: wrapper, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            return
        }

        // Display TODOs
        print("TODOs in: \(note.title)")
        print(String(repeating: "-", count: 60))

        for (i, todo) in todos.enumerated() {
            let checkbox = todo.isComplete ? "[x]" : "[ ]"
            let indentStr = String(repeating: "  ", count: todo.indent / 2)
            print("  \(i + 1). \(indentStr)\(checkbox) \(todo.text)")
        }
        print("")

        // Determine which item to toggle
        let itemToToggle: Int

        if let idx = toggleIndex {
            itemToToggle = idx
        } else {
            print("Enter number to toggle (or 'q' to quit): ", terminator: "")
            guard let answer = readLine(), answer.lowercased() != "q", let num = Int(answer) else {
                print("Cancelled.")
                return
            }
            itemToToggle = num
        }

        guard itemToToggle >= 1, itemToToggle <= todos.count else {
            print("Invalid item number. Must be 1-\(todos.count).")
            return
        }

        let targetTodo = todos[itemToToggle - 1]

        // Toggle the checkbox in the specific line
        var mutableLines = lines
        let targetLine = mutableLines[targetTodo.lineIndex]

        if targetTodo.isComplete {
            if let range = targetLine.range(of: "- [x]") {
                mutableLines[targetTodo.lineIndex] = targetLine.replacingCharacters(in: range, with: "- [ ]")
            }
        } else {
            if let range = targetLine.range(of: "- [ ]") {
                mutableLines[targetTodo.lineIndex] = targetLine.replacingCharacters(in: range, with: "- [x]")
            }
        }

        let newText = mutableLines.joined(separator: "\n")

        let updated = try await api.updateNote(record: record, newText: newText)

        let newState = targetTodo.isComplete ? "unchecked" : "checked"
        print("Toggled item \(itemToToggle) (\(newState)): \(targetTodo.text)")

        // Update local cache
        if NoteCache.exists(), var cache = try? NoteCache.load() {
            cache.upsertFromRecord(updated, text: newText)
            try? cache.save()
        }
    }

    // MARK: - Helpers

    private func findNoteRecord(api: CloudKitAPI, noteID: String) async throws -> CKRecord {
        let records = try await api.lookupRecords(ids: [noteID])
        if let r = records.first {
            return r
        }

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

    private func countOccurrences(of target: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: target, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }
}
