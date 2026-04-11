import ArgumentParser
import Foundation

public struct SyncCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync Bear notes to a local cache for fast search"
    )

    @Flag(name: .long, help: "Force a full re-sync (ignores existing cache)")
    var full: Bool = false

    @Flag(name: .shortAndLong, help: "Show per-note progress")
    var verbose: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    public init() {}

    public func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let force = self.full
        let verbose = self.verbose
        let json = self.json

        try runAsync {
            let engine = SyncEngine(api: api)
            let start = Date()

            if !json {
                if force {
                    print("Performing full sync...")
                } else if !NoteCache.exists() {
                    print("No local cache found. Performing initial sync...")
                } else {
                    print("Syncing...")
                }
            }

            let (cache, stats) = try await engine.sync(force: force, verbose: verbose)
            let elapsed = Date().timeIntervalSince(start)

            if json {
                let output: [String: Any] = [
                    "notesCount": cache.notes.count,
                    "added": stats.added,
                    "updated": stats.updated,
                    "deleted": stats.deleted,
                    "failed": stats.failed,
                    "elapsed": Double(String(format: "%.1f", elapsed))!,
                ]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                let elapsedStr = String(format: "%.1f", elapsed)
                print("Synced \(cache.notes.count) notes (\(stats.summary)) in \(elapsedStr)s")
            }
        }
    }
}
