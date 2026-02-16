import ArgumentParser
import Foundation

struct ExportNotes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export Bear notes as markdown files"
    )

    @Argument(help: "Output directory path")
    var outputDir: String

    @Option(name: .shortAndLong, help: "Filter by tag (partial match)")
    var tag: String?

    @Flag(name: .long, help: "Organize by tag folders")
    var byTag: Bool = false

    @Flag(name: .long, help: "Include YAML frontmatter with metadata")
    var frontmatter: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let outputDir = self.outputDir
        let tag = self.tag
        let byTag = self.byTag
        let frontmatter = self.frontmatter

        try runAsync {
            let outputURL = URL(fileURLWithPath: outputDir)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            print("Fetching note index...")
            let records = try await api.queryAllNotes(
                desiredKeys: ["uniqueIdentifier", "title", "text", "textADP", "tagsStrings", "sf_creationDate", "sf_modificationDate", "pinned"]
            )

            var filteredRecords = records
            if let tagFilter = tag?.lowercased() {
                filteredRecords = records.filter { record in
                    let note = BearNote(from: record)
                    return note.tags.contains { $0.lowercased().contains(tagFilter) }
                }
            }

            print("Exporting \(filteredRecords.count) notes...")

            var exported = 0
            var failed = 0

            for record in filteredRecords {
                let note = BearNote(from: record)

                // Get text: prefer textADP (inline), fall back to text asset
                let text: String
                if let textADP = record.fields["textADP"]?.value.stringValue {
                    text = textADP
                } else if let assetURL = note.textAssetURL {
                    do { text = try await api.downloadAsset(url: assetURL) }
                    catch { failed += 1; continue }
                } else {
                    failed += 1
                    continue
                }

                do {
                    let filename = sanitizeFilename(note.title) + ".md"

                    var fileURL: URL
                    if byTag, let firstTag = note.tags.first {
                        let tagDir = outputURL.appendingPathComponent(firstTag.replacingOccurrences(of: "/", with: "_"))
                        try FileManager.default.createDirectory(at: tagDir, withIntermediateDirectories: true)
                        fileURL = tagDir.appendingPathComponent(filename)
                    } else {
                        fileURL = outputURL.appendingPathComponent(filename)
                    }

                    var content = ""
                    if frontmatter {
                        let dateFormatter = ISO8601DateFormatter()
                        content += "---\n"
                        content += "title: \"\(note.title.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
                        content += "id: \(note.uniqueIdentifier)\n"
                        if !note.tags.isEmpty {
                            content += "tags: [\(note.tags.map { "\"\($0)\"" }.joined(separator: ", "))]\n"
                        }
                        if let d = note.creationDate {
                            content += "created: \(dateFormatter.string(from: d))\n"
                        }
                        if let d = note.modificationDate {
                            content += "modified: \(dateFormatter.string(from: d))\n"
                        }
                        if note.pinned { content += "pinned: true\n" }
                        content += "---\n\n"
                    }

                    content += text

                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                    exported += 1

                    if exported % 10 == 0 {
                        print("  \(exported)/\(filteredRecords.count)...")
                    }
                } catch {
                    print("  Failed: \(note.title) — \(error)")
                    failed += 1
                }
            }

            print("\nExported \(exported) notes to \(outputDir)")
            if failed > 0 {
                print("Failed: \(failed)")
            }
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        var sanitized = name.components(separatedBy: illegal).joined(separator: "_")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty { sanitized = "untitled" }
        if sanitized.count > 200 { sanitized = String(sanitized.prefix(200)) }
        return sanitized
    }
}
