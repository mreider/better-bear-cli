import ArgumentParser
import Foundation

public struct EditNote: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit a Bear note"
    )

    @Argument(help: "Note ID (uniqueIdentifier)")
    var noteID: String

    @Flag(name: .long, help: "Read new content from stdin (replaces entire note body)")
    var stdin: Bool = false

    @Option(name: .long, parsing: .unconditional, help: "Append text to the end of the note")
    var append: String?

    @Option(name: .long, parsing: .unconditional, help: "Insert appended text after the line containing this text (use with --append)")
    var after: String?

    @Option(name: .long, parsing: .unconditional, help: "Replace content under this heading (replaces until next heading of same or higher level)")
    var replaceSection: String?

    @Option(name: .long, parsing: .unconditional, help: "New content for the section (use with --replace-section)")
    var sectionContent: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Set front matter field (key=value, repeatable)")
    var setFm: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "Remove front matter field (key name, repeatable)")
    var removeFm: [String] = []

    @Flag(name: .long, help: "Open in $EDITOR for interactive editing")
    var editor: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    public init() {}

    public func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let noteID = self.noteID
        let useStdin = self.stdin
        let appendText = self.append
        let afterText = self.after
        let replaceSectionName = self.replaceSection
        let sectionContent = self.sectionContent
        let setFmPairs = self.setFm
        let removeFmKeys = self.removeFm
        let hasFmEdits = !setFmPairs.isEmpty || !removeFmKeys.isEmpty
        let useEditor = self.editor
        let json = self.json

        if json && useEditor {
            throw ValidationError("--json and --editor cannot be used together")
        }

        try runAsync {
            // Fetch the full note record
            let record = try await findNoteRecord(api: api, noteID: noteID)

            // Get current text content
            let currentText: String
            if let textADP = record.fields["textADP"]?.value.stringValue {
                currentText = textADP
            } else if let assetURL = BearNote(from: record).textAssetURL {
                currentText = try await api.downloadAsset(url: assetURL)
            } else {
                currentText = ""
            }

            let newText: String

            if useStdin {
                // Replace with stdin content
                var lines: [String] = []
                while let line = readLine(strippingNewline: false) {
                    lines.append(line)
                }
                newText = lines.joined()
            } else if let text = appendText {
                if let after = afterText {
                    // Insert after matching line
                    var lines = currentText.components(separatedBy: "\n")
                    let needle = after.lowercased()
                    var inserted = false
                    for i in 0..<lines.count {
                        let stripped = lines[i].replacingOccurrences(
                            of: "^#{1,6}\\s+", with: "", options: .regularExpression
                        ).lowercased()
                        if lines[i].lowercased().contains(needle) || stripped.contains(needle) {
                            lines.insert("", at: i + 1)
                            lines.insert(text, at: i + 2)
                            inserted = true
                            break
                        }
                    }
                    if !inserted {
                        lines.append("")
                        lines.append(text)
                    }
                    newText = lines.joined(separator: "\n")
                } else {
                    // Append to end
                    newText = currentText.hasSuffix("\n")
                        ? currentText + "\n" + text
                        : currentText + "\n\n" + text
                }
            } else if let sectionName = replaceSectionName {
                // Replace content under a heading
                let content = sectionContent ?? ""
                newText = replaceSection(in: currentText, heading: sectionName, with: content)
            } else if useEditor {
                // Open in $EDITOR
                let editorCmd = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
                let tmpDir = FileManager.default.temporaryDirectory
                let tmpFile = tmpDir.appendingPathComponent("bear-\(noteID.prefix(8)).md")

                try currentText.write(to: tmpFile, atomically: true, encoding: .utf8)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [editorCmd, tmpFile.path]
                process.standardInput = FileHandle.standardInput
                process.standardOutput = FileHandle.standardOutput
                process.standardError = FileHandle.standardError
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    print("Editor exited with error. Note not updated.")
                    return
                }

                newText = try String(contentsOf: tmpFile, encoding: .utf8)
                try FileManager.default.removeItem(at: tmpFile)

                if newText == currentText {
                    print("No changes made.")
                    return
                }
            } else if hasFmEdits {
                // Edit front matter fields only
                let (existingFm, body) = FrontMatter.parse(currentText)
                var fm = existingFm ?? FrontMatter()

                // Apply --set-fm pairs
                for pair in setFmPairs {
                    guard let eqIdx = pair.firstIndex(of: "=") else { continue }
                    let key = String(pair[pair.startIndex..<eqIdx]).trimmingCharacters(in: .whitespaces)
                    let value = String(pair[pair.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                    fm = fm.setting(key, value: value)
                }

                // Apply --remove-fm keys
                for key in removeFmKeys {
                    fm = fm.removing(key.trimmingCharacters(in: .whitespaces))
                }

                newText = fm.toNoteText(body: body)
            } else {
                if json {
                    throw ValidationError("No edit operation specified. Use --append, --stdin, --set-fm, or --remove-fm with --json.")
                }
                print("Specify one of: --stdin, --append, --editor, --set-fm, or --remove-fm")
                print("")
                print("Examples:")
                print("  bcli edit <id> --append 'New paragraph'")
                print("  bcli edit <id> --editor")
                print("  echo 'New content' | bcli edit <id> --stdin")
                return
            }

            let updated = try await api.updateNote(record: record, newText: newText)
            let note = BearNote(from: updated)

            if json {
                let output: [String: Any] = [
                    "id": note.uniqueIdentifier,
                    "title": note.title,
                    "updated": true,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print("Updated: \(note.title)")
                print("ID: \(note.uniqueIdentifier)")
            }

            // Update local cache
            if NoteCache.exists(), var cache = try? NoteCache.load() {
                cache.upsertFromRecord(updated, text: newText)
                try? cache.save()
            }
        }
    }

    private func findNoteRecord(api: CloudKitAPI, noteID: String) async throws -> CKRecord {
        // Try direct lookup first
        let records = try await api.lookupRecords(ids: [noteID])
        if let r = records.first {
            return r
        }

        // Search by uniqueIdentifier
        let allRecords = try await api.queryAllNotes()
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
        return full
    }

    /// Replace content under a heading, up to the next heading of same or higher level.
    private func replaceSection(in text: String, heading: String, with newContent: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let needle = heading.lowercased()

        // Find the heading line
        var headingIdx: Int? = nil
        var headingLevel = 0
        for (i, line) in lines.enumerated() {
            let stripped = line.replacingOccurrences(
                of: "^(#{1,6})\\s+", with: "", options: .regularExpression
            )
            let level = line.count - line.drop(while: { $0 == "#" }).count

            if level > 0 && (line.lowercased().contains(needle) || stripped.lowercased().contains(needle)) {
                headingIdx = i
                headingLevel = level
                break
            }
        }

        guard let startIdx = headingIdx else {
            // Heading not found, return unchanged
            return text
        }

        // Find end of section: next heading of same or higher level, or end of text
        var endIdx = lines.count
        for i in (startIdx + 1)..<lines.count {
            let line = lines[i]
            let level = line.count - line.drop(while: { $0 == "#" }).count
            if level > 0 && level <= headingLevel {
                endIdx = i
                break
            }
        }

        // Rebuild: keep heading line, replace content between heading and next heading
        var newLines = Array(lines[0...startIdx])
        if !newContent.isEmpty {
            newLines.append(newContent)
        }
        if endIdx < lines.count {
            newLines.append(contentsOf: lines[endIdx...])
        }
        return newLines.joined(separator: "\n")
    }
}
