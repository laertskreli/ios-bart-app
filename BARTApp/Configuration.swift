import Foundation

enum AppConfig {

    /// The Tailscale hostname for the OpenClaw Gateway
    static let gatewayHost: String = {
        // Check for environment variable first (useful for testing)
        if let envHost = ProcessInfo.processInfo.environment["BART_GATEWAY_HOST"] {
            return envHost
        }
        return "treals-mac-mini-1.tail3eabbc.ts.net"
    }()

    /// The port the OpenClaw Gateway listens on
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
