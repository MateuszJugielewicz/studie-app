import Foundation
// Minimal CoreLocation stand-in so the app's core logic compiles and tests on Linux (see scripts/test-core.sh).
struct CLLocationCoordinate2D { var latitude: Double; var longitude: Double }
final class CLLocation {
    let coordinate: CLLocationCoordinate2D
    init(latitude: Double, longitude: Double) { coordinate = .init(latitude: latitude, longitude: longitude) }
    func distance(from other: CLLocation) -> Double {
        let r = 6_371_000.0
        let dLat = (other.coordinate.latitude - coordinate.latitude) * .pi / 180
        let dLon = (other.coordinate.longitude - coordinate.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(coordinate.latitude * .pi / 180) * cos(other.coordinate.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}
