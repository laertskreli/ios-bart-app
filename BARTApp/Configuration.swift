import Foundation

enum AppConfig {

    /// The Tailscale hostname for the OpenClaw Gateway
    static let gatewayHost: String = {
        // Check for environment variable first (useful for testing)
        if let envHost = ProcessInfo.processInfo.environment["treals-mac-mini.tail3eabbc.ts.net"] {
            return envHost
        }
        return "treals-mac-mini.tail3eabbc.ts.net"
    }()

    /// The port for OpenClaw Gateway (direct Tailscale connection)
    static let gatewayPort: Int = 18789

    /// Enable debug logging
    static let debugLogging: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
