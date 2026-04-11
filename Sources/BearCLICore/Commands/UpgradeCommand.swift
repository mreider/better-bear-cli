import ArgumentParser
import Foundation

public struct UpgradeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "upgrade",
        abstract: "Upgrade bcli to the latest release"
    )

    @Flag(name: .long, help: "Check for updates without installing")
    var check: Bool = false

    public init() {}

    public func run() throws {
        let currentPath = findCurrentBinary()
        let currentVersion = BearCLI.configuration.version

        print("Current version: \(currentVersion)")
        print("Binary location: \(currentPath)")

        // Fetch latest release info from GitHub
        print("Checking for updates...")
        let latestVersion = try fetchLatestVersion()

        if latestVersion == currentVersion {
            print("Already up to date.")
            return
        }

        print("New version available: \(latestVersion)")

        if check {
            return
        }

        // Download and replace
        print("Downloading...")
        try downloadAndReplace(to: currentPath)

        print("")
        print("Upgraded to \(latestVersion)")
        print("")
        print("To apply, do one of:")
        print("  hash -r          # refresh current shell session")
        print("  exec $SHELL      # restart shell")
        print("")
        print("If you use the MCP server with Claude Desktop, restart Claude Desktop too.")
    }

    private func findCurrentBinary() -> String {
        // Find where bcli lives in PATH
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["bcli"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {}

        // Fallback: resolve from argv[0]
        let argv0 = CommandLine.arguments[0]
        if argv0.hasPrefix("/") {
            return argv0
        }

        // Default
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/bcli").path
    }

    private func fetchLatestVersion() throws -> String {
        let url = URL(string: "https://api.github.com/repos/mreider/better-bear-cli/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        var fetchError: Error?

        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            if let error = error {
                fetchError = error
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                fetchError = BearCLIError.networkError("Failed to parse release info")
                return
            }
            // Strip "v" prefix if present
            result = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }.resume()

        semaphore.wait()

        if let error = fetchError {
            throw error
        }
        guard let version = result else {
            throw BearCLIError.networkError("Could not determine latest version")
        }
        return version
    }

    private func downloadAndReplace(to targetPath: String) throws {
        let downloadURL = URL(string: "https://github.com/mreider/better-bear-cli/releases/latest/download/bcli-macos-universal.tar.gz")!
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let tarball = tmpDir.appendingPathComponent("bcli.tar.gz")

        // Download
        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error?

        URLSession.shared.downloadTask(with: downloadURL) { localURL, _, error in
            defer { semaphore.signal() }
            if let error = error {
                downloadError = error
                return
            }
            guard let localURL = localURL else {
                downloadError = BearCLIError.networkError("Download returned no data")
                return
            }
            do {
                try FileManager.default.moveItem(at: localURL, to: tarball)
            } catch {
                downloadError = error
            }
        }.resume()

        semaphore.wait()

        if let error = downloadError {
            throw error
        }

        // Extract
        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        extract.arguments = ["xzf", tarball.path, "-C", tmpDir.path]
        try extract.run()
        extract.waitUntilExit()

        guard extract.terminationStatus == 0 else {
            throw BearCLIError.networkError("Failed to extract archive")
        }

        let newBinary = tmpDir.appendingPathComponent("bcli")
        guard FileManager.default.fileExists(atPath: newBinary.path) else {
            throw BearCLIError.networkError("Binary not found in archive")
        }

        // Replace
        let targetURL = URL(fileURLWithPath: targetPath)
        if FileManager.default.fileExists(atPath: targetPath) {
            try FileManager.default.removeItem(at: targetURL)
        }

        // Ensure target directory exists
        let targetDir = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        try FileManager.default.moveItem(at: newBinary, to: targetURL)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: targetPath
        )
    }
}
