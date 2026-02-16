import ArgumentParser
import Foundation

struct ListTags: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "List all Bear tags"
    )

    @Flag(name: .long, help: "Show as flat list (no tree)")
    var flat: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let flat = self.flat
        let json = self.json

        try runAsync {
            let records = try await api.queryTags()
            let tags = records.map { BearTag(from: $0) }.sorted { $0.title < $1.title }

            if json {
                var output: [[String: Any]] = []
                for tag in tags {
                    output.append([
                        "title": tag.title,
                        "notesCount": tag.notesCount,
                        "pinned": tag.pinned,
                    ])
                }
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
                return
            }

            if flat {
                for tag in tags {
                    let pin = tag.pinned ? "* " : ""
                    print("\(pin)\(tag.title) (\(tag.notesCount))")
                }
            } else {
                printTree(tags)
            }

            print("\n\(tags.count) tags")
        }
    }

    private func printTree(_ tags: [BearTag]) {
        var tree: [String: [(String, BearTag)]] = [:]
        var roots: [BearTag] = []

        for tag in tags {
            let parts = tag.title.split(separator: "/", maxSplits: 1)
            if parts.count > 1 {
                let root = String(parts[0])
                let rest = String(parts[1])
                tree[root, default: []].append((rest, tag))
            } else {
                roots.append(tag)
            }
        }

        for root in roots {
            let pin = root.pinned ? "* " : ""
            print("\(pin)\(root.title) (\(root.notesCount))")
            if let children = tree[root.title] {
                for (i, (subpath, child)) in children.enumerated() {
                    let prefix = i == children.count - 1 ? "  └─ " : "  ├─ "
                    print("\(prefix)\(subpath) (\(child.notesCount))")
                }
            }
        }
    }
}
