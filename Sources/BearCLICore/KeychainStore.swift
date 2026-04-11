import Foundation

/// Wrapper around the macOS `security` CLI for Keychain operations.
/// No native Keychain framework needed — just shells out to `security`.
public struct KeychainStore {
    public static let service = "com.better-bear-cli"

    /// Save a value to the Keychain. Updates if it already exists.
    public static func save(account: String, data: String) throws {
        // -U: update if exists, -s: service, -a: account, -w: password data
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-generic-password",
            "-U",
            "-s", service,
            "-a", account,
            "-w", data,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw KeychainError.saveFailed(account: account)
        }
    }

    /// Load a value from the Keychain. Returns nil if not found.
    public static func load(account: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", service,
            "-a", account,
            "-w",
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return nil
            }
            return value
        } catch {
            return nil
        }
    }

    /// Delete a value from the Keychain.
    public static func delete(account: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "delete-generic-password",
            "-s", service,
            "-a", account,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        // Exit code 44 = item not found, which is fine for delete
        if process.terminationStatus != 0 && process.terminationStatus != 44 {
            throw KeychainError.deleteFailed(account: account)
        }
    }
}

public enum KeychainError: Error, CustomStringConvertible {
    case saveFailed(account: String)
    case deleteFailed(account: String)

    public var description: String {
        switch self {
        case .saveFailed(let account):
            return "Failed to save '\(account)' to Keychain."
        case .deleteFailed(let account):
            return "Failed to delete '\(account)' from Keychain."
        }
    }
}
