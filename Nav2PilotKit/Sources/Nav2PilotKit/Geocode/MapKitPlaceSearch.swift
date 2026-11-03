import Foundation
import MapKit

/// Search through Apple's MapKit local search (addresses and points of interest).
///
/// It needs network access to Apple's map service; there is no API key and nothing to configure. Without a region
/// Apple ranks the results for the whole country ("Ikea" near Basel gives Zurich first), so the phone's position,
/// when known, is passed as the region to look in first.
public final class MapKitPlaceSearch: PlaceSearch {
    private let nearby: () async -> LatLng?

    /// Half the side of the region around the phone, metres.
    static let regionHalfMeters = 25_000.0

    public init(nearby: @escaping () async -> LatLng? = { nil }) {
        self.nearby = nearby
    }

    public func isAvailable() -> Bool {
        return true
    }

    public func search(_ query: String, maxResults: Int) async throws -> [Destination] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        if let position = await nearby() {
            request.region = MapKitPlaceSearch.searchRegion(around: position)
        }

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch {
            let nsError = error as NSError
            // MapKit reports "nothing found" as an error; for us it is an empty result.
            if nsError.domain == MKErrorDomain && nsError.code == Int(MKError.Code.placemarkNotFound.rawValue) {
                return []
            }
            throw HttpClientError(error.localizedDescription)
        }

        var destinations: [Destination] = []
        for item in response.mapItems {
            if destinations.count >= maxResults {
                break
            }
            let coordinate = item.placemark.coordinate
            if !CoordinateRules.isValid(latitude: coordinate.latitude, longitude: coordinate.longitude) {
                continue
            }
            destinations.append(toDestination(item))
        }
        return destinations
    }

    /// A hint, not a limit: places farther away are still found when nothing nearer matches.
    static func searchRegion(around position: LatLng) -> MKCoordinateRegion {
        let center = CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude)
        return MKCoordinateRegion(center: center, latitudinalMeters: regionHalfMeters * 2, longitudinalMeters: regionHalfMeters * 2)
    }

    private func toDestination(_ item: MKMapItem) -> Destination {
        let coordinate = item.placemark.coordinate
        let address = item.placemark.title ?? ""
        var name = item.name ?? ""
        var details = address
        if name.isEmpty {
            // No place name: split "street, city, country" into a name and the rest, as the Android app does.
            name = address
            details = ""
            if let commaIndex = address.firstIndex(of: ",") {
                name = String(address[address.startIndex..<commaIndex]).trimmingCharacters(in: .whitespaces)
                details = String(address[address.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if details == name {
            details = ""
        }
        return Destination(latitude: coordinate.latitude, longitude: coordinate.longitude, name: name, details: details)
    }
}
