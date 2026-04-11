import ArgumentParser
import Foundation

public struct CreateNote: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new Bear note"
    )

    @Argument(help: "Note title")
    var title: String

    @Option(name: .shortAndLong, parsing: .unconditional, help: "Note body text (or use --stdin to read from stdin)")
    var body: String?

    @Option(name: .shortAndLong, help: "Tags (comma-separated)")
    var tags: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Front matter fields (key=value, space-separated)")
    var fm: [String] = []

    @Flag(name: .long, help: "Read note body from stdin")
    var stdin: Bool = false

    @Flag(name: .long, help: "Output created note ID only (for scripting)")
    var quiet: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    public init() {}

    public func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let title = self.title
        let quiet = self.quiet
        let json = self.json

        var bodyText = self.body ?? ""
        if self.stdin {
            var lines: [String] = []
            while let line = readLine(strippingNewline: false) {
                lines.append(line)
            }
            bodyText = lines.joined()
            // Remove trailing newline if present
            if bodyText.hasSuffix("\n") {
                bodyText = String(bodyText.dropLast())
            }
        }

        let tagList: [String]
        if let t = self.tags {
            tagList = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            tagList = []
        }

        let fmPairs = self.fm

        try runAsync {
            // Build front matter string if --fm flags were provided
            let frontMatterStr: String?
            if !fmPairs.isEmpty {
                let fm = FrontMatter(fromPairs: fmPairs)
                frontMatterStr = fm.toString()
            } else {
                frontMatterStr = nil
            }

            let record = try await api.createNote(title: title, text: bodyText, tags: tagList, frontMatter: frontMatterStr)
            let note = BearNote(from: record)

            if json {
                let output: [String: Any] = [
                    "id": note.uniqueIdentifier,
                    "title": note.title,
                    "tags": tagList,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else if quiet {
                print(note.uniqueIdentifier)
            } else {
                print("Created: \(note.title)")
                print("ID: \(note.uniqueIdentifier)")
                if !tagList.isEmpty {
                    print("Tags: \(tagList.joined(separator: ", "))")
                }
            }

            // Update local cache
            if NoteCache.exists(), var cache = try? NoteCache.load() {
                var markdown = "# \(title)"
                if !tagList.isEmpty { markdown += "\n" + tagList.map { "#\($0)" }.joined(separator: " ") }
                if !bodyText.isEmpty { markdown += "\n\n\(bodyText)" }
                cache.upsertFromRecord(record, text: markdown)
                try? cache.save()
            }
        }
    }
}
