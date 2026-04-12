import ArgumentParser
import Foundation

public struct MCPCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Manage MCP server for Claude Desktop and Claude Code",
        subcommands: [MCPInstall.self, MCPUninstall.self, MCPReinstall.self, MCPStatus.self]
    )

    public init() {}
}

// MARK: - Install

struct MCPInstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install Better Bear MCP server"
    )

    @Flag(name: .long, help: "Only configure Claude Desktop")
    var desktopOnly = false

    @Flag(name: .long, help: "Only configure Claude Code")
    var codeOnly = false

    @Flag(name: .long, help: "Write to claude_desktop_config.json instead of using .mcpb bundle")
    var json = false

    func run() throws {
        if !codeOnly {
            try installDesktop(useJson: json)
        }
        if !desktopOnly {
            installCode()
        }
    }
}

// MARK: - Uninstall

struct MCPUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove Better Bear MCP server"
    )

    @Flag(name: .long, help: "Only remove from Claude Desktop")
    var desktopOnly = false

    @Flag(name: .long, help: "Only remove from Claude Code")
    var codeOnly = false

    func run() throws {
        if !codeOnly {
            try uninstallDesktop()
        }
        if !desktopOnly {
            uninstallCode()
        }
    }
}

// MARK: - Reinstall

struct MCPReinstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reinstall",
        abstract: "Reinstall Better Bear MCP server (uninstall + install)"
    )

    func run() throws {
        try uninstallDesktop()
        uninstallCode()
        print("")
        try installDesktop(useJson: false)
        installCode()
    }
}

// MARK: - Status

struct MCPStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show MCP server configuration status"
    )

    func run() {
        // Claude Desktop
        let configURL = claudeDesktopConfigURL()
        let config = readClaudeConfig(at: configURL)
        let servers = config["mcpServers"] as? [String: Any]
        let desktopEntry = servers?[mcpKey] as? [String: Any]

        if let entry = desktopEntry {
            let cmd = entry["command"] as? String ?? "?"
            let args = (entry["args"] as? [String])?.joined(separator: " ") ?? ""
            print("Claude Desktop: installed (\(cmd) \(args))")
        } else {
            print("Claude Desktop: not installed")
        }

        // Claude Code
        if claudeCLIAvailable() {
            let result = runShell("claude mcp list 2>/dev/null")
            if result.status == 0 && result.output.contains(mcpKey) {
                print("Claude Code:    installed")
            } else {
                print("Claude Code:    not installed")
            }
        } else {
            print("Claude Code:    cli not found")
        }
    }
}

// MARK: - Shared

private let mcpKey = "better-bear"
private let legacyMcpKey = "better-bear-mcp"

private let mcpEntry: [String: Any] = [
    "command": "npx",
    "args": ["-y", "better-bear"],
]

// MARK: - Claude Desktop

private func claudeDesktopConfigURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
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

private let mcpbURL = "https://github.com/mreider/better-bear-cli/releases/latest/download/better-bear.mcpb"

@discardableResult
private func installDesktop(useJson: Bool) throws -> Bool {
    if useJson {
        return try installDesktopJson()
    }
    return try installDesktopMcpb()
}

private func installDesktopMcpb() throws -> Bool {
    // Download .mcpb bundle to temp directory
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("better-bear-install")
    try? FileManager.default.removeItem(at: tmpDir)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let mcpbPath = tmpDir.appendingPathComponent("better-bear.mcpb")

    print("Claude Desktop: downloading .mcpb bundle...")
    let result = runShell("curl -sL '\(mcpbURL)' -o '\(mcpbPath.path)'")
    guard result.status == 0, FileManager.default.fileExists(atPath: mcpbPath.path) else {
        print("Claude Desktop: failed to download .mcpb bundle")
        print("  Download manually: \(mcpbURL)")
        throw ExitCode.failure
    }

    // Remove any config-file entry to avoid duplicates
    cleanConfigFileEntry()

    // Open the .mcpb with Claude Desktop
    let open = runShell("open '\(mcpbPath.path)'")
    guard open.status == 0 else {
        print("Claude Desktop: failed to open .mcpb bundle")
        print("  Open manually: \(mcpbPath.path)")
        throw ExitCode.failure
    }

    print("Claude Desktop: opened .mcpb bundle — confirm install in Claude Desktop")
    print("  Uninstall via Claude Desktop UI or: bcli mcp uninstall")
    return true
}

private func installDesktopJson() throws -> Bool {
    let configURL = claudeDesktopConfigURL()
    var config = readClaudeConfig(at: configURL)

    if config["mcpServers"] == nil {
        config["mcpServers"] = [String: Any]()
    }
    guard var servers = config["mcpServers"] as? [String: Any] else {
        print("Claude Desktop: error — malformed mcpServers in config")
        throw ExitCode.failure
    }

    // Remove legacy key if present
    if servers[legacyMcpKey] != nil {
        servers.removeValue(forKey: legacyMcpKey)
    }

    if servers[mcpKey] != nil {
        print("Claude Desktop: already installed (config file)")
        return false
    }

    servers[mcpKey] = mcpEntry
    config["mcpServers"] = servers
    try writeClaudeConfig(config, to: configURL)
    print("Claude Desktop: installed via config file — restart Claude Desktop to activate")
    print("  Uninstall via: bcli mcp uninstall (Claude Desktop UI won't work for config-file servers)")
    return true
}

/// Remove config-file entries so they don't conflict with .mcpb extension
private func cleanConfigFileEntry() {
    let configURL = claudeDesktopConfigURL()
    guard FileManager.default.fileExists(atPath: configURL.path) else { return }
    var config = readClaudeConfig(at: configURL)
    guard var servers = config["mcpServers"] as? [String: Any] else { return }

    var changed = false
    if servers[mcpKey] != nil { servers.removeValue(forKey: mcpKey); changed = true }
    if servers[legacyMcpKey] != nil { servers.removeValue(forKey: legacyMcpKey); changed = true }
    if changed {
        config["mcpServers"] = servers
        try? writeClaudeConfig(config, to: configURL)
    }
}

@discardableResult
private func uninstallDesktop() throws -> Bool {
    let configURL = claudeDesktopConfigURL()
    var removed = false

    // Remove config-file entries
    if FileManager.default.fileExists(atPath: configURL.path),
       var config = readClaudeConfig(at: configURL) as [String: Any]?,
       var servers = config["mcpServers"] as? [String: Any] {
        let hadCurrent = servers[mcpKey] != nil
        let hadLegacy = servers[legacyMcpKey] != nil
        if hadCurrent || hadLegacy {
            servers.removeValue(forKey: mcpKey)
            servers.removeValue(forKey: legacyMcpKey)
            config["mcpServers"] = servers
            try writeClaudeConfig(config, to: configURL)
            print("Claude Desktop: removed config-file entry")
            removed = true
        }
    }

    if !removed {
        print("Claude Desktop: no config-file entry found")
        print("  If installed via .mcpb, remove it from Claude Desktop's connectors UI")
    }
    return removed
}

// MARK: - Claude Code

private func runShell(_ command: String) -> (status: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    } catch {
        return (1, "")
    }
}

private func claudeCLIAvailable() -> Bool {
    runShell("command -v claude").status == 0
}

private func installCode() {
    guard claudeCLIAvailable() else {
        print("Claude Code:    cli not found — to install manually run:")
        print("  claude mcp add \(mcpKey) -- npx -y better-bear")
        return
    }

    let check = runShell("claude mcp list 2>/dev/null")
    if check.status == 0 && check.output.contains(mcpKey) {
        print("Claude Code:    already installed")
        return
    }

    let result = runShell("claude mcp add \(mcpKey) -- npx -y better-bear")
    if result.status == 0 {
        print("Claude Code:    installed")
    } else {
        print("Claude Code:    failed — run manually:")
        print("  claude mcp add \(mcpKey) -- npx -y better-bear")
    }
}

private func uninstallCode() {
    guard claudeCLIAvailable() else {
        print("Claude Code:    cli not found — to remove manually run:")
        print("  claude mcp remove \(mcpKey)")
        return
    }

    let check = runShell("claude mcp list 2>/dev/null")
    guard check.status == 0 && check.output.contains(mcpKey) else {
        print("Claude Code:    not installed")
        return
    }

    let result = runShell("claude mcp remove \(mcpKey)")
    if result.status == 0 {
        print("Claude Code:    removed")
    } else {
        print("Claude Code:    failed — run manually:")
        print("  claude mcp remove \(mcpKey)")
    }
}
