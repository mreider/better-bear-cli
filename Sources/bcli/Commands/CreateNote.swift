import ArgumentParser
import Foundation

struct CreateNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new Bear note"
    )

    @Argument(help: "Note title")
    var title: String

    @Option(name: .shortAndLong, help: "Note body text (or use --stdin to read from stdin)")
    var body: String?

    @Option(name: .shortAndLong, help: "Tags (comma-separated)")
    var tags: String?

    @Flag(name: .long, help: "Read note body from stdin")
    var stdin: Bool = false

    @Flag(name: .long, help: "Output created note ID only (for scripting)")
    var quiet: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let title = self.title
        let quiet = self.quiet

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

        try runAsync {
            let record = try await api.createNote(title: title, text: bodyText, tags: tagList)
            let note = BearNote(from: record)

            if quiet {
                print(note.uniqueIdentifier)
            } else {
                print("Created: \(note.title)")
                print("ID: \(note.uniqueIdentifier)")
                if !tagList.isEmpty {
                    print("Tags: \(tagList.joined(separator: ", "))")
                }
            }
        }
    }
}
