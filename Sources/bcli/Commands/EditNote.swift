import ArgumentParser
import Foundation

struct EditNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit a Bear note"
    )

    @Argument(help: "Note ID (uniqueIdentifier)")
    var noteID: String

    @Flag(name: .long, help: "Read new content from stdin (replaces entire note body)")
    var stdin: Bool = false

    @Option(name: .long, help: "Append text to the end of the note")
    var append: String?

    @Flag(name: .long, help: "Open in $EDITOR for interactive editing")
    var editor: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let noteID = self.noteID
        let useStdin = self.stdin
        let appendText = self.append
        let useEditor = self.editor

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
                // Append to existing
                newText = currentText.hasSuffix("\n")
                    ? currentText + "\n" + text
                    : currentText + "\n\n" + text
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
            } else {
                print("Specify one of: --stdin, --append, or --editor")
                print("")
                print("Examples:")
                print("  bcli edit <id> --append 'New paragraph'")
                print("  bcli edit <id> --editor")
                print("  echo 'New content' | bcli edit <id> --stdin")
                return
            }

            let updated = try await api.updateNote(record: record, newText: newText)
            let note = BearNote(from: updated)
            print("Updated: \(note.title)")
            print("ID: \(note.uniqueIdentifier)")

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
}
