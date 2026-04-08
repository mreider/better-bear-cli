import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A minimal HTTP server that serves an Apple Sign-In page
/// and waits for the browser to POST back a ckWebAuthToken.
public class AuthServer {
    private let preferredPort: UInt16 = 19222
    private let timeoutSeconds: Int = 120
    private var serverSocket: Int32 = -1
    private var actualPort: UInt16 = 0
    private var receivedToken: String?
    private let tokenLock = NSLock()
    private var shouldStop = false

    private func authHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>bcli - Sign In</title>
            <link rel="icon" type="image/png" href="/favicon.ico">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
                    background: #1d1d1f;
                    min-height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: #d1d1d6;
                }
                .container {
                    background: #2c2c2e;
                    border-radius: 14px;
                    padding: 48px 44px;
                    max-width: 400px;
                    width: 90%;
                    box-shadow: 0 2px 20px rgba(0,0,0,0.35);
                    text-align: center;
                }
                .bear-icon {
                    width: 64px; height: 64px; margin: 0 auto 20px;
                    border-radius: 14px;
                }
                h1 {
                    font-size: 20px; font-weight: 600; margin-bottom: 6px;
                    color: #f5f5f7; letter-spacing: -0.2px;
                }
                .subtitle {
                    font-size: 13px; color: #98989d; margin-bottom: 28px;
                    line-height: 1.5;
                }
                #apple-sign-in-button {
                    position: absolute; width: 1px; height: 1px;
                    overflow: hidden; opacity: 0; pointer-events: none;
                }
                .custom-apple-btn {
                    display: inline-flex; align-items: center; justify-content: center;
                    gap: 8px; padding: 0 24px; height: 44px;
                    background: #fff; color: #1d1d1f; border: none; border-radius: 8px;
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                    font-size: 15px; font-weight: 500; cursor: pointer;
                    transition: opacity 0.15s;
                }
                .custom-apple-btn:hover { opacity: 0.88; }
                .custom-apple-btn svg { flex-shrink: 0; }
                #apple-sign-out-button { display: none; }
                .status {
                    margin-top: 20px; font-size: 13px; color: #98989d;
                    min-height: 20px;
                }
                .status.error { color: #ff6961; }
                .status.success {
                    color: #d4a853;
                    font-weight: 500;
                }
                .manual {
                    display: none; margin-top: 24px; padding: 18px;
                    background: #1d1d1f; border: 1px solid #3a3a3c;
                    border-radius: 10px; text-align: left;
                    font-size: 12px; line-height: 1.6; color: #98989d;
                }
                .manual strong { color: #d1d1d6; }
                .manual ol { margin: 10px 0 10px 18px; }
                .manual a { color: #d4a853; text-decoration: none; }
                .manual a:hover { text-decoration: underline; }
                .manual code {
                    background: #3a3a3c; padding: 2px 6px;
                    border-radius: 4px; font-size: 11px; color: #d1d1d6;
                }
                .manual input {
                    width: 100%; font-family: 'SF Mono', SFMono-Regular, Menlo, monospace;
                    font-size: 11px; background: #3a3a3c; color: #f5f5f7;
                    border: 1px solid #48484a; border-radius: 6px;
                    padding: 8px 10px; margin-top: 8px;
                    outline: none; transition: border-color 0.15s;
                }
                .manual input:focus { border-color: #d4a853; }
                .manual button {
                    margin-top: 8px; padding: 8px 18px;
                    background: #d4a853; color: #1d1d1f;
                    border: none; border-radius: 6px;
                    font-size: 12px; font-weight: 600; cursor: pointer;
                    transition: opacity 0.15s;
                }
                .manual button:hover { opacity: 0.85; }
                .debug { display: none; }
            </style>
        </head>
        <body>
            <div class="container">
                <img class="bear-icon" src="/icon" alt="Bear" />
                <h1>bcli Authentication</h1>
                <p class="subtitle">Sign in with your Apple ID to connect to your Bear notes via iCloud.</p>
                <button class="custom-apple-btn" id="custom-apple-btn" style="display:none" onclick="document.querySelector('#apple-sign-in-button .apple-auth-button').click()">
                    <svg width="16" height="19" viewBox="0 0 16 19" fill="none"><path d="M13.2 9.94c-.02-2.08 1.7-3.08 1.78-3.13-1-1.4-2.5-1.6-3.02-1.62-1.27-.13-2.52.76-3.17.76-.67 0-1.68-.74-2.77-.72A4.08 4.08 0 002.57 7.4c-1.5 2.58-.38 6.38 1.05 8.47.72 1.02 1.56 2.17 2.67 2.13 1.08-.04 1.49-.69 2.79-.69 1.29 0 1.66.69 2.78.66 1.16-.02 1.88-1.03 2.58-2.06.83-1.18 1.16-2.34 1.18-2.4-.03-.01-2.24-.85-2.26-3.4l-.14.83zM10.93 3.52A3.75 3.75 0 0011.8.5a3.86 3.86 0 00-2.5 1.3 3.6 3.6 0 00-.9 2.9 3.2 3.2 0 002.53-1.18z" fill="#1d1d1f"/></svg>
                    Sign in with Apple
                </button>
                <div id="apple-sign-in-button"></div>
                <div id="apple-sign-out-button"></div>
                <script>
                // Show our custom button once CloudKit JS renders the real (hidden) one
                (function() {
                    var btn = document.getElementById('apple-sign-in-button');
                    var custom = document.getElementById('custom-apple-btn');
                    var obs = new MutationObserver(function() {
                        if (btn.querySelector('.apple-auth-button')) {
                            obs.disconnect();
                            custom.style.display = 'inline-flex';
                        }
                    });
                    obs.observe(btn, {childList: true, subtree: true});
                })();
                </script>
                <p class="status" id="status">Loading CloudKit JS...</p>
                <div class="manual" id="manual">
                    <strong>Manual token flow:</strong>
                    <ol>
                        <li>Open <a href="https://web.bear.app" target="_blank">web.bear.app</a> and sign in</li>
                        <li>Open DevTools (Cmd+Option+I) then Network tab</li>
                        <li>Look for requests to <code>apple-cloudkit.com</code></li>
                        <li>Copy the <code>ckWebAuthToken</code> value from any request URL</li>
                    </ol>
                    <input type="text" id="manual-token" placeholder="Paste ckWebAuthToken here">
                    <button onclick="submitManualToken()">Submit Token</button>
                </div>
                <div class="debug" id="debug"></div>
            </div>
            <script>
                const PORT = \(actualPort);
                const debugEl = document.getElementById('debug');

                function log(msg) {
                    console.log('[bcli]', msg);
                    debugEl.textContent += msg + '\\n';
                }

                function setStatus(msg, cls) {
                    const el = document.getElementById('status');
                    el.textContent = msg;
                    el.className = 'status' + (cls ? ' ' + cls : '');
                }

                function showManual() {
                    document.getElementById('manual').style.display = 'block';
                }

                // Catch all errors
                window.addEventListener('error', function(e) { log('Error: ' + e.message); });
                window.addEventListener('unhandledrejection', function(e) { log('Rejection: ' + (e.reason && e.reason.message || e.reason)); });

                // Intercept both XHR and fetch to capture ckWebAuthToken from API URLs
                let capturedToken = null;

                function checkURLForToken(url) {
                    if (typeof url === 'string' && url.includes('ckWebAuthToken=')) {
                        const m = url.match(/ckWebAuthToken=([^&]+)/);
                        if (m && m[1] !== 'null' && m[1] !== 'undefined') {
                            capturedToken = decodeURIComponent(m[1]);
                            log('Captured token from URL (' + capturedToken.length + ' chars)');
                            return true;
                        }
                    }
                    return false;
                }

                // Intercept XMLHttpRequest
                const origOpen = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(method, url) {
                    checkURLForToken(url);
                    return origOpen.apply(this, arguments);
                };

                // Intercept fetch
                const origFetch = window.fetch;
                window.fetch = function(input, init) {
                    const url = (typeof input === 'string') ? input : (input && input.url) || '';
                    checkURLForToken(url);
                    return origFetch.apply(this, arguments);
                };

                // Listen for postMessage from Apple auth popup
                window.addEventListener('message', function(event) {
                    try {
                        const d = (typeof event.data === 'string') ? JSON.parse(event.data) : event.data;
                        log('postMessage from ' + event.origin + ': keys=' + Object.keys(d || {}).join(','));
                        // Look for token in various possible shapes
                        const t = d && (d.ckWebAuthToken || d.webAuthToken || d.authToken);
                        if (t) {
                            capturedToken = t;
                            log('Captured token from postMessage (' + t.length + ' chars)');
                        }
                    } catch(e) { /* not JSON, ignore */ }
                });

                async function sendToken(token) {
                    try {
                        const r = await fetch('http://localhost:' + PORT + '/callback', {
                            method: 'POST',
                            headers: {'Content-Type': 'application/json'},
                            body: JSON.stringify({token: token})
                        });
                        if (r.ok) {
                            document.getElementById('custom-apple-btn').style.display = 'none';
                            document.getElementById('apple-sign-in-button').style.display = 'none';
                            document.getElementById('manual').style.display = 'none';
                            var countdown = 5;
                            setStatus('Authenticated! Closing in ' + countdown + 's...', 'success');
                            var timer = setInterval(function() {
                                countdown--;
                                if (countdown <= 0) {
                                    clearInterval(timer);
                                    setStatus('Authenticated! Closing...', 'success');
                                    window.close();
                                    // window.close() may be blocked — update text as fallback
                                    setTimeout(function() {
                                        setStatus('Authenticated! You can close this tab.', 'success');
                                    }, 500);
                                } else {
                                    setStatus('Authenticated! Closing in ' + countdown + 's...', 'success');
                                }
                            }, 1000);
                            return true;
                        }
                    } catch(e) { log('Callback fetch failed: ' + e); }
                    return false;
                }

                function submitManualToken() {
                    const t = document.getElementById('manual-token').value.trim();
                    if (t) sendToken(t);
                    else setStatus('Paste a token first', 'error');
                }

                async function onSignedIn(container) {
                    setStatus('Signed in. Retrieving token...');
                    log('onSignedIn called');

                    // Strategy 1: Check if fetch/XHR interceptor already got the token
                    if (capturedToken) {
                        log('Already have token from network intercept (' + capturedToken.length + ' chars)');
                    }

                    // Strategy 2: Dump session internals for debugging
                    try {
                        const s = container._sessions && container._sessions['production'];
                        if (s) {
                            const keys = Object.keys(s).filter(k => k.toLowerCase().includes('token') || k.toLowerCase().includes('auth'));
                            log('Session token-related keys: ' + keys.join(', '));
                            for (const k of keys) {
                                const v = s[k];
                                if (typeof v === 'string') log('  ' + k + ' = ' + v.substring(0, 30) + '... (' + v.length + ' chars)');
                                else log('  ' + k + ' = ' + typeof v);
                            }
                        } else {
                            log('No production session found');
                        }
                    } catch(e) { log('Session inspect error: ' + e); }

                    // Strategy 3: Trigger a CloudKit API call to capture token from fetch/XHR URL
                    if (!capturedToken) {
                        try {
                            log('Triggering CloudKit query to capture token from network...');
                            const db = container.getDatabaseWithDatabaseScope(CloudKit.DatabaseScope.PRIVATE);
                            await db.performQuery({recordType:'SFNoteTag'}, {zoneName:'Notes'}, {resultsLimit:1}).catch(function(e){ log('Query rejected: ' + e); });
                        } catch(e) { log('Query error: ' + e); }
                        if (capturedToken) log('Got token from network intercept after query');
                    }

                    let token = capturedToken;

                    if (token) {
                        const sent = await sendToken(token);
                        if (!sent) {
                            setStatus('Could not reach CLI. Use the manual flow below.', 'error');
                            showManual();
                            document.getElementById('manual-token').value = token;
                        }
                    } else {
                        setStatus('Could not extract token automatically.', 'error');
                        showManual();
                    }
                }
            </script>
            <script id="ck-script" src="https://cdn.apple-cloudkit.com/ck/2/cloudkit.js"
                    onerror="log('CloudKit JS failed to load'); setStatus('CloudKit JS failed to load.', 'error'); showManual();"></script>
            <script>
                (function() {
                    log('CloudKit type: ' + typeof CloudKit);
                    if (typeof CloudKit === 'undefined') {
                        setStatus('CloudKit JS not available.', 'error');
                        showManual();
                        return;
                    }
                    try {
                        log('Calling CloudKit.configure...');
                        CloudKit.configure({
                            containers: [{
                                containerIdentifier: 'iCloud.net.shinyfrog.bear',
                                apiTokenAuth: {
                                    apiToken: 'ce59f955ec47e744f720aa1d2816a4e985e472d8b859b6c7a47b81fd36646307',
                                    persist: false,
                                    signInButton: { id: 'apple-sign-in-button', theme: 'white' },
                                    signOutButton: { id: 'apple-sign-out-button' }
                                },
                                environment: 'production'
                            }]
                        });
                        log('CloudKit.configure OK');

                        var container = CloudKit.getDefaultContainer();
                        log('Got container, calling setUpAuth...');

                        container.setUpAuth().then(function(uid) {
                            log('setUpAuth resolved, uid=' + uid);
                            setStatus('');
                            if (uid) {
                                onSignedIn(container);
                            }
                        }).catch(function(err) {
                            log('setUpAuth failed: ' + (err && err.message || err));
                            setStatus('CloudKit auth setup failed. Use manual flow.', 'error');
                            showManual();
                        });

                        container.whenUserSignsIn().then(function() {
                            log('whenUserSignsIn resolved');
                            onSignedIn(container);
                        }).catch(function(err) {
                            log('whenUserSignsIn error: ' + (err && err.message || err));
                        });
                    } catch(e) {
                        log('Init error: ' + e.message);
                        setStatus('CloudKit init failed. Use manual flow.', 'error');
                        showManual();
                    }
                })();
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Bear Icon

    private var cachedIcon: Data?

    /// Load Bear's app icon from the installed app bundle.
    /// Converts the .icns to a 128x128 PNG via sips (built into macOS).
    /// Caches the result for subsequent requests.
    private func loadBearIcon() -> Data? {
        if let cached = cachedIcon { return cached }

        let icnsPath = "/Applications/Bear.app/Contents/Resources/AppIcon-26.icns"
        guard FileManager.default.fileExists(atPath: icnsPath) else { return nil }

        let tmpPng = NSTemporaryDirectory() + "bcli-bear-icon.png"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        proc.arguments = ["-s", "format", "png", "-z", "128", "128", icnsPath, "--out", tmpPng]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = try Data(contentsOf: URL(fileURLWithPath: tmpPng))
            try? FileManager.default.removeItem(atPath: tmpPng)
            cachedIcon = data
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Socket Server

    private func createServerSocket() throws -> (Int32, UInt16) {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw AuthServerError.socketCreationFailed(String(cString: strerror(errno)))
        }

        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        let ports: [UInt16] = [preferredPort, 0]
        for port in ports {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if bindResult == 0 {
                var boundAddr = sockaddr_in()
                var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        getsockname(sock, sockPtr, &addrLen)
                    }
                }
                return (sock, UInt16(bigEndian: boundAddr.sin_port))
            }
        }

        close(sock)
        throw AuthServerError.bindFailed("Could not bind to any port")
    }

    /// Read a full HTTP request from a blocking socket.
    private func readRequest(_ sock: Int32) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 16384)
        var data = Data()
        var contentLength = 0
        var headersComplete = false

        // Set read timeout
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        while data.count < 65536 {
            let n = recv(sock, &buffer, buffer.count, 0)
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])

            guard let raw = String(data: data, encoding: .utf8) else { continue }

            if !headersComplete {
                if let range = raw.range(of: "\r\n\r\n") {
                    headersComplete = true
                    // Parse Content-Length from headers
                    for line in raw[..<range.lowerBound].split(separator: "\r\n") {
                        if line.lowercased().hasPrefix("content-length:") {
                            contentLength = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
                        }
                    }
                    let bodyLen = raw[range.upperBound...].utf8.count
                    if bodyLen >= contentLength { return data }
                }
            } else {
                if let range = raw.range(of: "\r\n\r\n") {
                    let bodyLen = raw[range.upperBound...].utf8.count
                    if bodyLen >= contentLength { return data }
                }
            }
        }

        return data.isEmpty ? nil : data
    }

    private func parseRequest(_ data: Data) -> (method: String, path: String, body: String)? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let parts = raw.components(separatedBy: "\r\n\r\n")
        let lines = parts[0].components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let tokens = first.split(separator: " ", maxSplits: 2)
        guard tokens.count >= 2 else { return nil }
        let body = parts.count > 1 ? parts[1] : ""
        return (String(tokens[0]), String(tokens[1]), body)
    }

    private func respondData(_ sock: Int32, status: Int, statusText: String, contentType: String, body: Data) {
        var header = "HTTP/1.1 \(status) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: public, max-age=3600\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"
        var data = Data(header.utf8)
        data.append(body)
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = Darwin.send(sock, ptr.advanced(by: sent), data.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    private func respond(_ sock: Int32, status: Int, statusText: String, contentType: String, body: String) {
        var r = "HTTP/1.1 \(status) \(statusText)\r\n"
        r += "Content-Type: \(contentType)\r\n"
        r += "Content-Length: \(body.utf8.count)\r\n"
        r += "Connection: close\r\n"
        r += "Access-Control-Allow-Origin: *\r\n"
        r += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        r += "Access-Control-Allow-Headers: Content-Type\r\n"
        r += "\r\n\(body)"
        let data = Data(r.utf8)
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = Darwin.send(sock, ptr.advanced(by: sent), data.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    private func handleClient(_ clientSocket: Int32) {
        defer { close(clientSocket) }

        // CRITICAL: Set client socket to blocking mode.
        // It inherits non-blocking from the server socket.
        let flags = fcntl(clientSocket, F_GETFL)
        _ = fcntl(clientSocket, F_SETFL, flags & ~O_NONBLOCK)

        guard let data = readRequest(clientSocket),
              let req = parseRequest(data) else {
            respond(clientSocket, status: 400, statusText: "Bad Request",
                    contentType: "text/plain", body: "Bad Request")
            return
        }

        switch (req.method, req.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            respond(clientSocket, status: 200, statusText: "OK",
                    contentType: "text/html; charset=utf-8", body: authHTML())

        case ("GET", "/icon"):
            if let iconData = loadBearIcon() {
                respondData(clientSocket, status: 200, statusText: "OK",
                            contentType: "image/png", body: iconData)
            } else {
                respond(clientSocket, status: 404, statusText: "Not Found",
                        contentType: "text/plain", body: "")
            }

        case ("GET", "/favicon.ico"):
            if let iconData = loadBearIcon() {
                respondData(clientSocket, status: 200, statusText: "OK",
                            contentType: "image/png", body: iconData)
            } else {
                respond(clientSocket, status: 204, statusText: "No Content",
                        contentType: "text/plain", body: "")
            }

        case ("GET", "/health"):
            respond(clientSocket, status: 200, statusText: "OK",
                    contentType: "application/json", body: "{\"status\":\"ok\"}")

        case ("POST", "/callback"):
            if let jsonData = req.body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let t = json["token"] as? String, !t.isEmpty {
                tokenLock.lock()
                receivedToken = t
                tokenLock.unlock()
                respond(clientSocket, status: 200, statusText: "OK",
                        contentType: "application/json", body: "{\"status\":\"ok\"}")
                // Delay shutdown so the browser receives the response and
                // the countdown JS can run before the CLI process exits.
                Thread.sleep(forTimeInterval: 6.0)
                shouldStop = true
            } else {
                respond(clientSocket, status: 400, statusText: "Bad Request",
                        contentType: "application/json", body: "{\"error\":\"Missing token\"}")
            }

        case ("OPTIONS", _):
            respond(clientSocket, status: 204, statusText: "No Content",
                    contentType: "text/plain", body: "")

        default:
            respond(clientSocket, status: 404, statusText: "Not Found",
                    contentType: "text/plain", body: "Not Found")
        }
    }

    // MARK: - Public Interface

    public func startAndWaitForToken() -> String? {
        do {
            let (sock, port) = try createServerSocket()
            serverSocket = sock
            actualPort = port

            guard listen(serverSocket, 5) == 0 else {
                close(serverSocket)
                return nil
            }

            // Set server socket to non-blocking for accept loop
            let flags = fcntl(serverSocket, F_GETFL)
            _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

            let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

            while Date() < deadline && !shouldStop {
                var clientAddr = sockaddr_in()
                var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        accept(serverSocket, sockPtr, &addrLen)
                    }
                }

                if clientSocket >= 0 {
                    Thread { self.handleClient(clientSocket) }.start()
                } else {
                    // No connection waiting, sleep briefly
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }

            close(serverSocket)

            tokenLock.lock()
            let token = receivedToken
            tokenLock.unlock()
            return token
        } catch {
            fputs("Error starting auth server: \(error)\n", stderr)
            return nil
        }
    }

    public var port: UInt16 { actualPort }

    public func openInBrowser() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["http://localhost:\(actualPort)/"]
        try? p.run()
    }
}

public enum AuthServerError: Error, CustomStringConvertible {
    case socketCreationFailed(String)
    case bindFailed(String)

    public var description: String {
        switch self {
        case .socketCreationFailed(let msg): return "Socket creation failed: \(msg)"
        case .bindFailed(let msg): return "Bind failed: \(msg)"
        }
    }
}
