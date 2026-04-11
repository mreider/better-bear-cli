import ArgumentParser
import Foundation

public struct MCPCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Manage MCP server for Claude Desktop",
        subcommands: [MCPInstall.self, MCPUninstall.self]
    )

    public init() {}
}

struct MCPInstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install Better Bear MCP server into Claude Desktop configuration"
    )

    @Option(name: .long, help: "Path to the MCP server entry point (dist/index.js)")
    var path: String?

    func run() throws {
        // Find the MCP server entry point
        let serverPath = try findServerEntryPoint()

        // Read or create Claude Desktop config
        let configURL = claudeDesktopConfigURL()
        var config = readClaudeConfig(at: configURL)

        // Ensure mcpServers key exists
        if config["mcpServers"] == nil {
            config["mcpServers"] = [String: Any]()
        }

        guard var mcpServers = config["mcpServers"] as? [String: Any] else {
            print("Error: malformed mcpServers in Claude Desktop config.")
            throw ExitCode.failure
        }

        // Add/update the bear entry
        mcpServers["better-bear-mcp"] = [
            "command": "node",
            "args": [serverPath],
        ] as [String: Any]
        config["mcpServers"] = mcpServers

        // Write the config back
        try writeClaudeConfig(config, to: configURL)

        print("Better Bear MCP server installed.")
        print("  Server: \(serverPath)")
        print("  Config: \(configURL.path)")
        print("")
        print("Restart Claude Desktop to activate.")
    }

    private func findServerEntryPoint() throws -> String {
        // 1. Explicit --path
        if let p = path {
            let url = URL(fileURLWithPath: p)
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("Error: MCP server not found at \(p)")
                throw ExitCode.failure
            }
            return url.standardizedFileURL.path
        }

        // 2. Relative to bcli binary (development layout)
        let bcliURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let devCandidates = [
            bcliURL.appendingPathComponent("../../mcp-server/dist/index.js").standardized.path,
            bcliURL.appendingPathComponent("../mcp-server/dist/index.js").standardized.path,
        ]
        for candidate in devCandidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        // 3. npm global install
        let npmRoot = runShellCommand("npm root -g")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let root = npmRoot {
            let npmPath = (root as NSString).appendingPathComponent("better-bear-mcp/dist/index.js")
            if FileManager.default.fileExists(atPath: npmPath) {
                return npmPath
            }
        }

        // 4. Common locations relative to home
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let homeCandidates = [
            (home as NSString).appendingPathComponent("chats/better-bear-cli/mcp-server/dist/index.js"),
        ]
        for candidate in homeCandidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        print("Error: Could not find the MCP server entry point (dist/index.js).")
        print("")
        print("Build it first:")
        print("  cd mcp-server && npm install && npm run build")
        print("")
        print("Or specify the path directly:")
        print("  bcli mcp install --path /path/to/mcp-server/dist/index.js")
        throw ExitCode.failure
    }
}

struct MCPUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove Better Bear MCP server from Claude Desktop configuration"
    )

    func run() throws {
        let configURL = claudeDesktopConfigURL()

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            print("Claude Desktop config not found. Nothing to uninstall.")
            return
        }

        var config = readClaudeConfig(at: configURL)

        guard var mcpServers = config["mcpServers"] as? [String: Any] else {
            print("No MCP servers configured. Nothing to uninstall.")
            return
        }

        guard mcpServers["better-bear-mcp"] != nil else {
            print("Better Bear MCP server is not installed. Nothing to uninstall.")
            return
        }

        mcpServers.removeValue(forKey: "better-bear-mcp")
        config["mcpServers"] = mcpServers

        try writeClaudeConfig(config, to: configURL)

        print("Better Bear MCP server removed.")
        print("Restart Claude Desktop to apply.")
    }
}

// MARK: - Helpers

private func claudeDesktopConfigURL() -> URL {
    let appSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
        .appendingPathComponent("Claude")
    return appSupport.appendingPathComponent("claude_desktop_config.json")
}

private func readClaudeConfig(at url: URL) -> [String: Any] {
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

private func writeClaudeConfig(_ config: [String: Any], to url: URL) throws {
    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

private func runShellCommand(_ command: String) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}
