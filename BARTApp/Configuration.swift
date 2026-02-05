import Foundation

enum AppConfig {

    /// The gateway host - Tailscale Serve URL for anywhere access
    static let gatewayHost: String = {
        // Check for environment variable first (useful for testing)
        if let envHost = ProcessInfo.processInfo.environment["BART_GATEWAY_HOST"] {
            return envHost
        }

        // Always use Tailscale hostname - works from simulator and device
        return "treals-mac-mini.tail3eabbc.ts.net"
    }()

    /// The port for OpenClaw Gateway (443 for Tailscale Serve HTTPS)
    static let gatewayPort: Int = 443

    /// Use secure WebSocket - wss:// for Tailscale Serve
    static let useSSL: Bool = true

    /// Enable debug logging
    static let debugLogging: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
