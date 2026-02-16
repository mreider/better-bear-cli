import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A minimal HTTP server that serves an Apple Sign-In page
/// and waits for the browser to POST back a ckWebAuthToken.
class AuthServer {
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
            <link rel="icon" href="data:,">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: linear-gradient(135deg, #fdf2f0 0%, #fce8e4 50%, #f5d5cf 100%);
                    min-height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: #333;
                }
                .container {
                    background: white;
                    border-radius: 16px;
                    padding: 48px;
                    max-width: 480px;
                    width: 90%;
                    box-shadow: 0 8px 32px rgba(0,0,0,0.08);
                    text-align: center;
                }
                h1 { font-size: 24px; font-weight: 600; margin-bottom: 8px; color: #1a1a1a; }
                .subtitle { font-size: 15px; color: #666; margin-bottom: 32px; line-height: 1.5; }
                #apple-sign-in-button { min-height: 44px; display: flex; justify-content: center; }
                #apple-sign-out-button { display: none; }
                .status { margin-top: 24px; font-size: 14px; color: #666; min-height: 20px; }
                .status.error { color: #d32f2f; }
                .status.success { color: #2e7d32; }
                .manual {
                    display: none; margin-top: 24px; padding: 20px; background: #f5f5f5;
                    border-radius: 8px; text-align: left; font-size: 13px; line-height: 1.6;
                }
                .manual ol { margin: 12px 0 12px 20px; }
                .manual code { background: #e8e8e8; padding: 2px 6px; border-radius: 3px; font-size: 12px; }
                .manual input {
                    width: 100%; font-family: monospace; font-size: 12px;
                    border: 1px solid #ddd; border-radius: 4px; padding: 8px; margin-top: 8px;
                }
                .manual button {
                    margin-top: 8px; padding: 8px 16px; background: #333; color: white;
                    border: none; border-radius: 6px; font-size: 13px; cursor: pointer;
                }
                .debug { display: none; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>bcli Authentication</h1>
                <p class="subtitle">Sign in with your Apple ID to connect to your Bear notes via iCloud.</p>
                <div id="apple-sign-in-button"></div>
                <div id="apple-sign-out-button"></div>
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
                            setStatus('Authenticated! You can close this tab.', 'success');
                            document.getElementById('apple-sign-in-button').style.display = 'none';
                            document.getElementById('manual').style.display = 'none';
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
                                    signInButton: { id: 'apple-sign-in-button', theme: 'black' },
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

        case ("GET", "/favicon.ico"):
            respond(clientSocket, status: 204, statusText: "No Content",
                    contentType: "text/plain", body: "")

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

    func startAndWaitForToken() -> String? {
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

    var port: UInt16 { actualPort }

    func openInBrowser() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["http://localhost:\(actualPort)/"]
        try? p.run()
    }
}

enum AuthServerError: Error, CustomStringConvertible {
    case socketCreationFailed(String)
    case bindFailed(String)

    var description: String {
        switch self {
        case .socketCreationFailed(let msg): return "Socket creation failed: \(msg)"
        case .bindFailed(let msg): return "Bind failed: \(msg)"
        }
    }
}
