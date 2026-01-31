import Foundation

struct DeviceIdentity: Codable {
    let nodeId: String
    let displayName: String
    var pairingToken: String?
    var pairedAt: Date?

    static let storageKey = "com.bart.deviceIdentity"
}

enum PairingState: Equatable {
    case unpaired
    case pendingApproval(code: String, requestId: String)
    case paired(token: String)
    case failed(String)
}
