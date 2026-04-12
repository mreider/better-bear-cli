import Foundation

/// Non-destructive version check. Caches results for 24 hours.
/// Prints a one-liner to stderr so it doesn't break JSON output or pipes.
public enum VersionCheck {
    private static var cacheFile: URL {
        AuthConfig.configDir.appendingPathComponent("version-check.json")
    }

    /// Check for updates. Only hits GitHub API once per day (cached).
    /// Prints to stderr if update available. Fast no-op when cached.
    public static func check() {
        // Read cache
        if let cached = readCache(), cached.checkedAt.timeIntervalSinceNow > -86400 {
            // Checked within 24 hours
            if let latest = cached.latestVersion, latest != cached.currentVersion {
                printUpdateNotice(latest)
            }
            return
        }

        // Fetch from GitHub (with short timeout)
        guard let url = URL(string: "https://api.github.com/repos/mreider/better-bear-cli/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 3 // Don't hang

        let semaphore = DispatchSemaphore(value: 0)
        var latestVersion: String?

        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }
            latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }.resume()

        // Wait up to 3 seconds
        _ = semaphore.wait(timeout: .now() + 3)

        // Cache the result
        let current = currentVersion()
        writeCache(VersionCache(
            latestVersion: latestVersion,
            currentVersion: current,
            checkedAt: Date()
        ))

        if let latest = latestVersion, latest != current {
            printUpdateNotice(latest)
        }
    }

    private static func printUpdateNotice(_ latest: String) {
        FileHandle.standardError.write(
            Data("\n  Update available: \(latest) (current: \(currentVersion())). Run `bcli upgrade` to update.\n\n".utf8)
        )
    }

    static func currentVersion() -> String {
        // The version from the release tag, or fallback
        BearCLI.configuration.version
    }

    // MARK: - Cache

    private struct VersionCache: Codable {
        let latestVersion: String?
        let currentVersion: String
        let checkedAt: Date
    }

    private static func readCache() -> VersionCache? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VersionCache.self, from: data)
    }

    private static func writeCache(_ cache: VersionCache) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: AuthConfig.configDir, withIntermediateDirectories: true
        )
        try? data.write(to: cacheFile)
    }
}
