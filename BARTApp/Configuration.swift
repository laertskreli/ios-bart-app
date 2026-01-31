import Foundation

enum Configuration {

    /// The Tailscale hostname for the OpenClaw Gateway
    /// Replace this with your Mac Mini's Tailscale hostname
    static let gatewayHost: String = {
        // Check for environment variable first (useful for testing)
        if let envHost = ProcessInfo.processInfo.environment["BART_GATEWAY_HOST"] {
            return envHost
        }

        // Default to your Tailscale hostname
        // TODO: Replace with your actual Tailscale hostname
        return "mac-mini.tail12345.ts.net"
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
