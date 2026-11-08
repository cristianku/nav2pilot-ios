import Foundation

/// The kind of a place in OpenStreetMap, its main tag as "key:value" ("shop:furniture"), as people call it. The
/// labels are the Android app's; Apple's categories are turned into the same kinds (see MapKitPlaceSearch).
public enum PlaceKinds {
    /// "Furniture store" for "shop:furniture"; "" for addresses and for what is no help to name.
    public static func label(_ kind: String) -> String {
        guard let colon = kind.firstIndex(of: ":") else {
            return ""
        }
        let key = String(kind[kind.startIndex..<colon])
        let value = String(kind[kind.index(after: colon)...])
        if key.isEmpty || value.isEmpty {
            return ""
        }
        if let known = labels[kind] {
            return known
        }
        if unnamedKeys.contains(key) || value == "yes" {
            if key == "shop" {
                return "Shop"
            }
            return ""
        }
        var words = value.replacingOccurrences(of: "_", with: " ")
        words = words.prefix(1).uppercased() + words.dropFirst()
        if key == "shop" {
            return words + " shop"
        }
        return words
    }

    /// The category of the map's places menu the kind belongs to, for its symbol; nil for the others.
    public static func category(_ kind: String) -> PlaceCategory? {
        for category in PlaceCategory.allCases {
            if category.tags.contains(kind) {
                return category
            }
        }
        return nil
    }

    public static func isShop(_ kind: String) -> Bool {
        return kind.hasPrefix("shop:")
    }

    /// A town, a region or a street: an area more than a place.
    public static func isArea(_ kind: String) -> Bool {
        let key = keyOf(kind)
        if key == "place" {
            return kind != "place:house"
        }
        return key == "boundary" || (key == "highway" && category(kind) == nil)
    }

    /// An address or a building, without a kind of its own.
    public static func isAddress(_ kind: String) -> Bool {
        return keyOf(kind) == "building" || kind == "place:house"
    }

    /// The first of `category`'s tags the element has, "amenity:fast_food"; the category's first without one.
    static func fromTags(_ tags: [String: Any], category: PlaceCategory) -> String {
        for tag in category.tags {
            let key = keyOf(tag)
            let value = String(tag.dropFirst(key.count + 1))
            if Json.string(tags, key).trimmingCharacters(in: .whitespacesAndNewlines) == value {
                return tag
            }
        }
        return category.tags.first ?? ""
    }

    /// The element's main tag, "shop:furniture": what it is rather than what building it is in; "" without one.
    static func mainTag(_ tags: [String: Any]) -> String {
        for key in mainKeys {
            let value = Json.string(tags, key).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return key + ":" + value
            }
        }
        return ""
    }

    private static func keyOf(_ kind: String) -> String {
        guard let colon = kind.firstIndex(of: ":") else {
            return ""
        }
        return String(kind[kind.startIndex..<colon])
    }

    // a fuel station with a shop is a fuel station first
    private static let mainKeys = ["amenity", "shop", "tourism", "leisure", "railway", "aeroway", "highway"]

    // what names a building, an address or an area, not what is there
    private static let unnamedKeys: Set<String> = ["building", "boundary", "landuse", "place", "highway", "addr", "entrance"]

    private static let labels: [String: String] = [
        // shops
        "shop:supermarket": "Supermarket",
        "shop:furniture": "Furniture store",
        "shop:convenience": "Convenience store",
        "shop:bakery": "Bakery",
        "shop:butcher": "Butcher",
        "shop:clothes": "Clothing store",
        "shop:shoes": "Shoe store",
        "shop:electronics": "Electronics store",
        "shop:hardware": "Hardware store",
        "shop:doityourself": "DIY store",
        "shop:garden_centre": "Garden centre",
        "shop:department_store": "Department store",
        "shop:mall": "Shopping centre",
        "shop:car": "Car dealer",
        "shop:car_repair": "Car repair",
        "shop:tyres": "Tyre shop",
        "shop:bicycle": "Bicycle shop",
        "shop:books": "Bookshop",
        "shop:sports": "Sports shop",
        "shop:toys": "Toy store",
        "shop:florist": "Florist",
        "shop:hairdresser": "Hairdresser",
        "shop:optician": "Optician",
        "shop:chemist": "Drugstore",
        "shop:beverages": "Drinks store",
        "shop:kiosk": "Kiosk",
        "shop:mobile_phone": "Phone shop",
        "shop:pet": "Pet shop",
        "shop:jewelry": "Jeweller",
        "shop:interior_decoration": "Home decor store",
        "shop:houseware": "Houseware store",
        // food and drink
        "amenity:restaurant": "Restaurant",
        "amenity:fast_food": "Fast food",
        "amenity:cafe": "Café",
        "amenity:bar": "Bar",
        "amenity:pub": "Pub",
        "amenity:ice_cream": "Ice cream",
        // on the road
        "amenity:fuel": "Fuel station",
        "amenity:charging_station": "Charging station",
        "amenity:parking": "Parking",
        "amenity:parking_entrance": "Parking entrance",
        "amenity:car_wash": "Car wash",
        "amenity:car_rental": "Car rental",
        "highway:services": "Service area",
        "highway:rest_area": "Rest area",
        // services
        "amenity:pharmacy": "Pharmacy",
        "amenity:hospital": "Hospital",
        "amenity:clinic": "Clinic",
        "amenity:doctors": "Doctor",
        "amenity:dentist": "Dentist",
        "amenity:veterinary": "Vet",
        "amenity:bank": "Bank",
        "amenity:atm": "ATM",
        "amenity:post_office": "Post office",
        "amenity:police": "Police",
        "amenity:fire_station": "Fire station",
        "amenity:townhall": "Town hall",
        "amenity:school": "School",
        "amenity:kindergarten": "Kindergarten",
        "amenity:university": "University",
        "amenity:college": "College",
        "amenity:library": "Library",
        "amenity:cinema": "Cinema",
        "amenity:theatre": "Theatre",
        "amenity:place_of_worship": "Place of worship",
        "amenity:marketplace": "Market",
        "amenity:toilets": "Toilets",
        // staying and visiting
        "tourism:hotel": "Hotel",
        "tourism:motel": "Motel",
        "tourism:hostel": "Hostel",
        "tourism:guest_house": "Guest house",
        "tourism:apartment": "Holiday flat",
        "tourism:camp_site": "Campsite",
        "tourism:caravan_site": "Caravan site",
        "tourism:museum": "Museum",
        "tourism:attraction": "Attraction",
        "tourism:viewpoint": "Viewpoint",
        "tourism:zoo": "Zoo",
        "tourism:theme_park": "Theme park",
        "leisure:park": "Park",
        "leisure:sports_centre": "Sports centre",
        "leisure:fitness_centre": "Gym",
        "leisure:swimming_pool": "Swimming pool",
        "leisure:water_park": "Water park",
        "leisure:stadium": "Stadium",
        "leisure:golf_course": "Golf course",
        "leisure:playground": "Playground",
        // travel
        "railway:station": "Train station",
        "aeroway:aerodrome": "Airport",
        "amenity:ferry_terminal": "Ferry terminal",
        // areas
        "place:city": "City",
        "place:town": "Town",
        "place:village": "Village",
        "place:hamlet": "Hamlet",
        "place:suburb": "District",
        "place:quarter": "District",
        "place:neighbourhood": "Neighbourhood",
        "place:locality": "Place",
        "highway:motorway": "Motorway",
        "highway:trunk": "Road",
        "highway:primary": "Road",
        "highway:secondary": "Road",
        "highway:tertiary": "Road",
        "highway:unclassified": "Road",
        "highway:residential": "Street",
        "highway:living_street": "Street",
        "highway:pedestrian": "Pedestrian street",
        "natural:peak": "Mountain",
        "natural:water": "Lake",
    ]
}
