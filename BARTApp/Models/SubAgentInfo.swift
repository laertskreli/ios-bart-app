import Foundation

struct SubAgentInfo: Codable, Identifiable, Equatable {
    let id: String
    let sessionKey: String
    let parentSessionKey: String
    let label: String
    let task: String
    let spawnedAt: Date
    var status: SubAgentStatus
    var announceResult: AnnounceResult?
}

enum SubAgentStatus: String, Codable {
    case running
    case completed
    case failed
}

struct AnnounceResult: Codable, Equatable {
    let status: String
    let result: String?
    let notes: String?
    let runtime: TimeInterval?
    let tokens: Int?
    let cost: Double?
}
