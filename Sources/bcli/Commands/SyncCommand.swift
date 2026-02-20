import ArgumentParser
import Foundation

struct SyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync Bear notes to a local cache for fast search"
    )

    @Flag(name: .long, help: "Force a full re-sync (ignores existing cache)")
    var full: Bool = false

    @Flag(name: .shortAndLong, help: "Show per-note progress")
    var verbose: Bool = false

    func run() throws {
        let auth = try loadAuth()
        let api = CloudKitAPI(auth: auth)
        let force = self.full
        let verbose = self.verbose

        try runAsync {
            let engine = SyncEngine(api: api)
            let start = Date()

            if force {
                print("Performing full sync...")
            } else if !NoteCache.exists() {
                print("No local cache found. Performing initial sync...")
            } else {
                print("Syncing...")
            }

            let (cache, stats) = try await engine.sync(force: force, verbose: verbose)
            let elapsed = String(format: "%.1f", Date().timeIntervalSince(start))

            print("Synced \(cache.notes.count) notes (\(stats.summary)) in \(elapsed)s")
        }
    }
}
