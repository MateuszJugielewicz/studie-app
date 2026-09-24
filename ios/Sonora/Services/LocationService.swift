import CoreLocation
import UIKit
import MapKit
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var location: CLLocation?
    var authorization: CLAuthorizationStatus = .notDetermined
    var cityName: String?

    /// Used when location is denied so the app still shows something sensible.
    static let fallback = CLLocation(latitude: 37.9838, longitude: 23.7275) // Athens

    var effectiveLocation: CLLocation { location ?? Self.fallback }
    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermission() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.location = latest
            await self.reverseGeocode(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func reverseGeocode(_ location: CLLocation) async {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        cityName = placemarks?.first?.locality
    }

    /// Resolves a typed address to coordinates (used by studio onboarding).
    static func geocode(_ address: String) async throws -> CLLocationCoordinate2D? {
        let placemarks = try await CLGeocoder().geocodeAddressString(address)
        return placemarks.first?.location?.coordinate
    }

    /// Opens turn-by-turn directions in Apple Maps, or Google Maps when installed and preferred.
    static func openDirections(to studio: Studio, preferGoogle: Bool = false) {
        if preferGoogle,
           let url = URL(string: "comgooglemaps://?daddr=\(studio.latitude),\(studio.longitude)&directionsmode=transit"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: studio.coordinate))
        item.name = studio.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
