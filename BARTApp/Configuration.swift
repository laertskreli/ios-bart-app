import Foundation

enum AppConfig {

    /// The gateway host - Tailscale IP for anywhere access
    static let gatewayHost: String = {
        // Check for environment variable first (useful for testing)
        if let envHost = ProcessInfo.processInfo.environment["BART_GATEWAY_HOST"] {
            return envHost
        }

        #if targetEnvironment(simulator)
        return "localhost"
        #else
        // Use Tailscale IP - works from anywhere (home, cellular, etc.)
        return "100.102.89.44"
        #endif
    }()

    /// The port for OpenClaw Gateway
    static let gatewayPort: Int = 18789

    /// Use secure WebSocket - ws:// for local network
    static let useSSL: Bool = false

    /// Enable debug logging
    static let debugLogging: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
