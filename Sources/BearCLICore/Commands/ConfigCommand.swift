import ArgumentParser
import Foundation

public struct ConfigCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage bcli configuration",
        subcommands: [SetConfig.self, GetConfig.self]
    )

    public init() {}
}

struct SetConfig: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set a configuration value"
    )

    @Argument(help: "Configuration key (e.g., anthropic-key)")
    var key: String

    func run() throws {
        switch key {
        case "anthropic-key":
            print("Enter your Anthropic API key: ", terminator: "")
            guard let value = readLine(), !value.isEmpty else {
                print("No key provided. Cancelled.")
                return
            }
            try KeychainStore.save(account: "anthropic-key", data: value)
            print("Anthropic API key saved to macOS Keychain.")
        default:
            print("Unknown config key: \(key)")
            print("Available keys: anthropic-key")
        }
    }
}

struct GetConfig: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Check a configuration value"
    )

    @Argument(help: "Configuration key (e.g., anthropic-key)")
    var key: String

    func run() throws {
        switch key {
        case "anthropic-key":
            if KeychainStore.load(account: "anthropic-key") != nil {
                print("Anthropic API key: stored")
            } else {
                print("Anthropic API key: not configured")
                print("Set it with: bcli config set anthropic-key")
            }
        default:
            print("Unknown config key: \(key)")
            print("Available keys: anthropic-key")
        }
    }
}
