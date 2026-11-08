import Foundation
import MapKit

/// Search through Apple's MapKit local search (addresses and points of interest), with each place's category,
/// phone number and web page when Apple has them.
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
            destinations.append(MapKitPlaceSearch.toDestination(item))
        }
        return destinations
    }

    /// A hint, not a limit: places farther away are still found when nothing nearer matches.
    static func searchRegion(around position: LatLng) -> MKCoordinateRegion {
        let center = CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude)
        return MKCoordinateRegion(center: center, latitudinalMeters: regionHalfMeters * 2, longitudinalMeters: regionHalfMeters * 2)
    }

    static func toDestination(_ item: MKMapItem) -> Destination {
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
        var website = ""
        if let url = item.url {
            // only a web page opens from the details
            website = PlaceInfo.webAddress(url.absoluteString)
        }
        return Destination(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: name,
            details: details,
            kind: MapKitPlaceSearch.kind(item.pointOfInterestCategory),
            phone: (item.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            website: website
        )
    }

    /// Apple's category of a point of interest as OpenStreetMap's main tag, for the same labels and symbols as the
    /// places from OpenStreetMap ("store" is any shop: OpenStreetMap often says which); "" without one.
    static func kind(_ category: MKPointOfInterestCategory?) -> String {
        guard let category = category else {
            return ""
        }
        if let kind = kinds[category] {
            return kind
        }
        if #available(iOS 18.0, macOS 15.0, *) {
            return newerKind(category)
        }
        return ""
    }

    private static let kinds: [MKPointOfInterestCategory: String] = [
        .airport: "aeroway:aerodrome",
        .amusementPark: "tourism:theme_park",
        .aquarium: "tourism:aquarium",
        .atm: "amenity:atm",
        .bakery: "shop:bakery",
        .bank: "amenity:bank",
        .beach: "natural:beach",
        .brewery: "craft:brewery",
        .cafe: "amenity:cafe",
        .campground: "tourism:camp_site",
        .carRental: "amenity:car_rental",
        .evCharger: "amenity:charging_station",
        .fireStation: "amenity:fire_station",
        .fitnessCenter: "leisure:fitness_centre",
        .foodMarket: "shop:supermarket",
        .gasStation: "amenity:fuel",
        .hospital: "amenity:hospital",
        .hotel: "tourism:hotel",
        .laundry: "shop:laundry",
        .library: "amenity:library",
        .marina: "leisure:marina",
        .movieTheater: "amenity:cinema",
        .museum: "tourism:museum",
        .nationalPark: "boundary:national_park",
        .nightlife: "amenity:bar",
        .park: "leisure:park",
        .parking: "amenity:parking",
        .pharmacy: "amenity:pharmacy",
        .police: "amenity:police",
        .postOffice: "amenity:post_office",
        .publicTransport: "public_transport:station",
        .restaurant: "amenity:restaurant",
        .restroom: "amenity:toilets",
        .school: "amenity:school",
        .stadium: "leisure:stadium",
        .store: "shop:yes",
        .theater: "amenity:theatre",
        .university: "amenity:university",
        .winery: "craft:winery",
        .zoo: "tourism:zoo",
    ]

    /// Some of the categories Apple added in iOS 18.
    @available(iOS 18.0, macOS 15.0, *)
    private static func newerKind(_ category: MKPointOfInterestCategory) -> String {
        switch category {
        case .automotiveRepair: return "shop:car_repair"
        case .beauty: return "shop:beauty"
        case .castle: return "historic:castle"
        case .conventionCenter: return "amenity:conference_centre"
        case .golf: return "leisure:golf_course"
        case .landmark: return "tourism:attraction"
        case .musicVenue: return "amenity:music_venue"
        case .spa: return "leisure:spa"
        default: return ""
        }
    }
}
