import ArgumentParser
import Foundation

public struct ExportNotes: ParsableCommand {
    public static let configuration = CommandConfiguration(
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

    public init() {}

    public func run() throws {
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
                var text: String
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

                        // Build Bear metadata front matter
                        var exportFm = FrontMatter(fields: [
                            ("title", "\"\(note.title.replacingOccurrences(of: "\"", with: "\\\""))\""),
                            ("id", note.uniqueIdentifier),
                        ])
                        if !note.tags.isEmpty {
                            exportFm = exportFm.setting("tags", value: "[\(note.tags.map { "\"\($0)\"" }.joined(separator: ", "))]")
                        }
                        if let d = note.creationDate {
                            exportFm = exportFm.setting("created", value: dateFormatter.string(from: d))
                        }
                        if let d = note.modificationDate {
                            exportFm = exportFm.setting("modified", value: dateFormatter.string(from: d))
                        }
                        if note.pinned {
                            exportFm = exportFm.setting("pinned", value: "true")
                        }

                        // Merge with any existing user front matter in the note
                        let (userFm, bodyWithoutFm) = FrontMatter.parse(text)
                        if let userFm = userFm {
                            // User fields take precedence, then add Bear metadata
                            exportFm = userFm.merging(with: exportFm)
                            text = bodyWithoutFm
                        }

                        content += exportFm.toString()
                        content += "\n"
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
