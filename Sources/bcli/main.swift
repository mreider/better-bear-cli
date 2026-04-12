import BearCLICore
import Foundation

// Check for updates after command exits (non-blocking, cached 24h, prints to stderr)
signal(SIGINT, SIG_DFL)
atexit { VersionCheck.check() }

BearCLI.main()
