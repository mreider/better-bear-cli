import ArgumentParser
import Foundation

public struct AttachFile: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Attach a file or image to a Bear note"
    )

    @Argument(help: "Note ID (uniqueIdentifier)")
    var noteID: String

    @Argument(help: "Path to the file to attach (or filename when using --base64)")
    var filePath: String

    @Option(name: .long, parsing: .unconditional, help: "Base64-encoded file content (alternative to file path)")
    var base64: String?

    @Flag(name: .long, help: "Insert after the title line instead of at the end")
    var prepend: Bool = false

    @Option(name: .long, parsing: .unconditional, help: "Insert after the line containing this text")
    var after: String?

    @Option(name: .long, parsing: .unconditional, help: "Insert before the line containing this text")
    var before: String?

    @Option(name: .long, parsing: .unconditional, help: "Insert after this line number (1-based)")
    var atLine: Int?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    public init() {}

    public func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let noteID = self.noteID
        let filePath = self.filePath
        let json = self.json

        let fileData: Data
        let fileName: String
        let ext: String

        if let b64 = self.base64 {
            // Base64 mode: filePath is the filename, data comes from --base64
            guard let decoded = Data(base64Encoded: b64) else {
                throw BearCLIError.networkError("Invalid base64 data")
            }
            fileData = decoded
            fileName = URL(fileURLWithPath: filePath).lastPathComponent
            ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        } else {
            // File path mode
            let fileURL = URL(fileURLWithPath: filePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw BearCLIError.networkError("File not found: \(filePath)")
            }
            fileData = try Data(contentsOf: fileURL)
            fileName = fileURL.lastPathComponent
            ext = fileURL.pathExtension.lowercased()
        }

        // Determine MIME type
        let contentType = mimeType(for: ext)

        // Determine position
        let prepend = self.prepend
        let afterText = self.after
        let beforeText = self.before
        let atLine = self.atLine

        try runAsync {
            // Find the note
            let record = try await findNoteRecord(api: api, noteID: noteID)

            // Resolve position from text matching
            let position: CloudKitAPI.AttachPosition
            if let text = afterText {
                position = resolvePosition(record: record, after: text)
            } else if let text = beforeText {
                position = resolvePosition(record: record, before: text)
            } else if let line = atLine {
                position = .at(line)
            } else if prepend {
                position = .prepend
            } else {
                position = .append
            }

            // Attach the file
            let (imageRecord, updatedNote) = try await api.attachToNote(
                noteRecord: record,
                fileData: fileData,
                fileName: fileName,
                contentType: contentType,
                position: position
            )

            let noteTitle = updatedNote.fields["title"]?.value.stringValue ?? ""

            if json {
                let output: [String: Any] = [
                    "id": imageRecord.recordName,
                    "noteId": noteID,
                    "noteTitle": noteTitle,
                    "fileName": fileName,
                    "fileSize": fileData.count,
                    "attached": true,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                print("Attached: \(fileName)")
                print("Note: \(noteTitle)")
                print("Record ID: \(imageRecord.recordName)")
                print("Size: \(fileData.count) bytes")
            }

            // Update local cache
            if NoteCache.exists(), var cache = try? NoteCache.load() {
                // Re-fetch text for cache update
                var text = ""
                if let textADP = updatedNote.fields["textADP"]?.value.stringValue {
                    text = textADP
                }
                cache.upsertFromRecord(updatedNote, text: text)
                try? cache.save()
            }
        }
    }

    private func findNoteRecord(api: CloudKitAPI, noteID: String) async throws -> CKRecord {
        let records = try await api.lookupRecords(ids: [noteID])
        if let r = records.first {
            return r
        }

        let allRecords = try await api.queryAllNotes(
            desiredKeys: ["uniqueIdentifier", "title", "text", "textADP", "tagsStrings",
                          "sf_creationDate", "sf_modificationDate", "pinned",
                          "files", "hasImages", "hasFiles"]
        )

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

    /// Match a line against search text. Also matches headings — e.g. "My Heading"
    /// matches "# My Heading", "## My Heading", etc.
    private func lineMatches(_ line: String, _ needle: String) -> Bool {
        let lower = line.lowercased()
        let target = needle.lowercased()
        if lower.contains(target) { return true }
        // Strip markdown heading prefix and try again
        let stripped = line.replacingOccurrences(
            of: "^#{1,6}\\s+", with: "", options: .regularExpression
        ).lowercased()
        return stripped.contains(target)
    }

    private func resolvePosition(record: CKRecord, after text: String) -> CloudKitAPI.AttachPosition {
        let noteText = record.fields["textADP"]?.value.stringValue ?? ""
        let lines = noteText.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if lineMatches(line, text) {
                return .at(i + 1)
            }
        }
        return .append
    }

    private func resolvePosition(record: CKRecord, before text: String) -> CloudKitAPI.AttachPosition {
        let noteText = record.fields["textADP"]?.value.stringValue ?? ""
        let lines = noteText.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if lineMatches(line, text) {
                return .at(i)
            }
        }
        return .append
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "svg": return "image/svg+xml"
        case "avif": return "image/avif"
        case "pdf": return "application/pdf"
        case "mp4": return "video/mp4"
        case "mp3": return "audio/mpeg"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}
