import ArgumentParser
import Foundation

public struct BearCLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "bcli",
        abstract: "CLI for Bear notes via CloudKit",
        version: BearCLI.appVersion,
        subcommands: [
            AuthCommand.self,
            ListNotes.self,
            GetNote.self,
            ListTags.self,
            SearchNotes.self,
            CreateNote.self,
            EditNote.self,
            ArchiveNote.self,
            TrashNote.self,
            TagCommand.self,
            TodoCommand.self,
            StatsCommand.self,
            DuplicatesCommand.self,
            HealthCommand.self,
            AttachFile.self,
            ExportNotes.self,
            SyncCommand.self,
            MCPCommand.self,
            UpgradeCommand.self,
            ConfigCommand.self,
            ContextCommand.self,
        ]
    )

    // Injected by CI at build time via sed; falls back to "dev" for local builds
    public static let appVersion = "0.4.0"

    public init() {}
}

// Shared auth loader
public func loadAuth() throws -> AuthConfig {
    do {
        return try AuthConfig.load()
    } catch {
        throw BearCLIError.authNotConfigured
    }
}

/// Run an async block synchronously using a semaphore
public func runAsync(_ block: @escaping () async throws -> Void) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var thrownError: Error?

    Task {
        do {
            try await block()
        } catch {
            thrownError = error
        }
        semaphore.signal()
    }

    semaphore.wait()
    if let error = thrownError {
        throw error
    }
}
