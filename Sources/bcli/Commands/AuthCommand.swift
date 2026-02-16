import ArgumentParser
import Foundation

struct AuthCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Authenticate with iCloud for Bear access"
    )

    @Option(name: .long, help: "Paste your ckWebAuthToken directly (skips browser flow)")
    var token: String?

    @Flag(name: .long, help: "Force browser-based authentication even if already authenticated")
    var browser: Bool = false

    func run() throws {
        let webAuthToken: String

        if let t = token {
            // Direct token mode - use the provided token
            webAuthToken = t
        } else {
            // Browser-based authentication flow
            print("Starting browser-based authentication...")
            print("")

            let server = AuthServer()

            // Start the server in a background thread so we can open the browser
            var serverToken: String?
            let serverThread = Thread {
                serverToken = server.startAndWaitForToken()
            }
            serverThread.start()

            // Give the server a moment to start listening
            Thread.sleep(forTimeInterval: 0.5)

            // Open the auth page in the default browser
            print("Opening your browser for Apple Sign-In...")
            print("If the browser doesn't open, visit: http://localhost:\(server.port)/")
            print("")
            server.openInBrowser()

            print("Waiting for authentication (timeout: 2 minutes)...")
            print("Complete the sign-in in your browser, then return here.")
            print("")

            // Wait for the server thread to finish
            while !serverThread.isFinished {
                Thread.sleep(forTimeInterval: 0.5)
            }

            guard let receivedToken = serverToken else {
                print("Authentication timed out or failed.")
                print("")
                print("Alternative: get the token manually:")
                print("  1. Open https://web.bear.app/ in Chrome")
                print("  2. Sign in with your Apple ID")
                print("  3. Open DevTools (Cmd+Option+I) -> Network tab")
                print("  4. Filter by 'apple-cloudkit'")
                print("  5. Copy the ckWebAuthToken value from any request URL")
                print("")
                print("Then run:  bcli auth --token '<YOUR_TOKEN>'")
                return
            }

            webAuthToken = receivedToken
            print("Token received from browser!")
        }

        // Validate the token by making a test API call
        let config = AuthConfig(
            ckWebAuthToken: webAuthToken,
            ckAPIToken: AuthConfig.apiToken,
            savedAt: Date()
        )

        try runAsync {
            let api = CloudKitAPI(auth: config)
            do {
                let zones = try await api.listZones()
                let zoneNames = zones.map { $0.zoneID.zoneName }
                print("Authenticated successfully.")
                print("Zones found: \(zoneNames.joined(separator: ", "))")
                try config.save()
                print("Token saved to \(AuthConfig.configFile.path)")
            } catch BearCLIError.authExpired {
                print("Error: Token is invalid or expired.")
                print("Try running `bcli auth` again to get a fresh token.")
            }
        }
    }
}
