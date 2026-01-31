import Foundation
import CoreLocation

struct LocationShare: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let timestamp: Date
    let ttl: TimeInterval

    var isExpired: Bool {
        Date() > timestamp.addingTimeInterval(ttl)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
