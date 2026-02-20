import ArgumentParser
import Foundation

struct BearCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bcli",
        abstract: "CLI for Bear notes via CloudKit",
        version: "0.3.0",
        subcommands: [
            AuthCommand.self,
            ListNotes.self,
            GetNote.self,
            ListTags.self,
            SearchNotes.self,
            CreateNote.self,
            EditNote.self,
            TrashNote.self,
            TodoCommand.self,
            ExportNotes.self,
            SyncCommand.self,
        ]
    )
}

// Shared auth loader
func loadAuth() throws -> AuthConfig {
    do {
        return try AuthConfig.load()
    } catch {
        throw BearCLIError.authNotConfigured
    }
}

/// Run an async block synchronously using a semaphore
func runAsync(_ block: @escaping () async throws -> Void) throws {
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

BearCLI.main()
