import Foundation

/// What is known about a place besides its name and address; "" for what is not known.
public struct PlaceInfo: Equatable {
    /// As mapped in OpenStreetMap, "Mo-Fr 08:00-18:00; Sa 08:00-12:00": `OpeningHours.parse` reads it.
    public var openingHours: String
    public var phone: String
    /// An http or https address, nothing else.
    public var website: String
    /// What OpenStreetMap says the place is, "shop:furniture" (see PlaceKinds); "" when unknown.
    public var kind: String

    public init(openingHours: String = "", phone: String = "", website: String = "", kind: String = "") {
        self.openingHours = openingHours
        self.phone = phone
        self.website = website
        self.kind = kind
    }

    /// Nothing to show in the details: no opening hours, no phone and no website.
    public func isEmpty() -> Bool {
        return openingHours.isEmpty && phone.isEmpty && website.isEmpty
    }

    /// From an element's OpenStreetMap tags.
    static func fromTags(_ tags: [String: Any]) -> PlaceInfo {
        return PlaceInfo(
            openingHours: firstTag(tags, ["opening_hours"]),
            // several numbers are separated by ";": the first is the main one
            phone: firstPart(firstTag(tags, ["phone", "contact:phone"])),
            website: webAddress(firstPart(firstTag(tags, ["website", "contact:website", "url"]))),
            kind: PlaceKinds.mainTag(tags)
        )
    }

    /// `text` as an address the browser can open; "" for anything that is not a web page ("javascript:", "tel:").
    public static func webAddress(_ text: String) -> String {
        if text.isEmpty || text.contains(" ") {
            return ""
        }
        let lower = text.lowercased()
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            return text
        }
        // "www.ikea.ch" is often mapped so
        if !text.contains(":") && text.contains(".") {
            return "https://" + text
        }
        return ""
    }

    /// "ikea.com/ch/de/stores/pratteln" for "https://www.ikea.com/ch/de/stores/pratteln/".
    public static func shortWebAddress(_ address: String) -> String {
        var text = address
        for prefix in ["https://", "http://", "www."] {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
            }
        }
        while text.hasSuffix("/") {
            text = String(text.dropLast())
        }
        return text
    }

    /// "tel:+41848801100" for "+41 848 801 100", for the phone app; "" when there is no number in it.
    public static func phoneLink(_ phone: String) -> String {
        var digits = ""
        for character in phone {
            if character.isASCII && character.isNumber {
                digits.append(character)
            } else if character == "+" && digits.isEmpty {
                digits.append(character)
            }
        }
        if digits.filter({ character in character != "+" }).isEmpty {
            return ""
        }
        return "tel:" + digits
    }

    private static func firstTag(_ tags: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            let value = Json.string(tags, key).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private static func firstPart(_ text: String) -> String {
        guard let semicolon = text.firstIndex(of: ";") else {
            return text
        }
        return String(text[text.startIndex..<semicolon]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Opening hours (and the phone and website when Apple has none) of search results, from OpenStreetMap through
/// the Overpass API.
///
/// Apple's results carry no OpenStreetMap id, so each is looked for by its name around its own position. The
/// servers get only the names of the places found and their coordinates (rounded to about 10 m), never the phone's
/// position or what was typed. One request for a whole list of results, and what was found is kept for the rest
/// of the session; a lookup no server answered is not kept, so it is tried again next time.
@MainActor
public final class PlaceInfoLookup {
    private let http: HttpClient
    private let endpoints: ([LatLng]) -> [String]

    // the oldest out first
    private var known: [String: PlaceInfo] = [:]
    private var order: [String] = []
    // asked by an earlier lookup that has not finished: that one reports them
    private var pending: Set<String> = []

    // a list of results and the destinations chosen in a session
    nonisolated static let maxKnown = 200

    // only extra information: better none than a wait
    nonisolated static let serverTimeoutSeconds: TimeInterval = 6

    // how far from Apple's pin the OpenStreetMap place may be: its outline, for a building, not its middle
    nonisolated static let radiusMeters = 200
    // and its middle, for the largest stores: a place with the same name farther away is another one
    nonisolated static let matchMeters = 600.0

    // a longer name is cut: the words that tell it apart come first
    private nonisolated static let maxWords = 8

    public init(http: HttpClient, endpoints: @escaping ([LatLng]) -> [String] = OverpassEndpoints.forPoints) {
        self.http = http
        self.endpoints = endpoints
    }

    /// The info of `destinations` by `PlaceInfoLookup.key`, also when OpenStreetMap has none (empty). Those no
    /// server could be asked about are left out. `found` gets what each server gave as soon as it answers: the
    /// Swiss server is quick, the next ones may take seconds.
    @discardableResult
    public func lookup(_ destinations: [Destination], found report: ([String: PlaceInfo]) -> Void = { _ in }) async -> [String: PlaceInfo] {
        var found: [String: PlaceInfo] = [:]
        var missing: [Destination] = []
        var seen: Set<String> = []
        for destination in destinations {
            if !PlaceInfoLookup.wants(destination) {
                continue
            }
            let key = PlaceInfoLookup.key(destination)
            if seen.contains(key) || pending.contains(key) {
                continue
            }
            seen.insert(key)
            if let info = remembered(key) {
                found[key] = info
            } else {
                missing.append(destination)
            }
        }
        if !found.isEmpty {
            report(found)
        }
        if missing.isEmpty {
            return found
        }

        var asked: [String] = []
        for destination in missing {
            asked.append(PlaceInfoLookup.key(destination))
        }
        pending.formUnion(asked)
        defer {
            pending.subtract(asked)
        }

        var points: [LatLng] = []
        for destination in missing {
            points.append(LatLng(latitude: destination.latitude, longitude: destination.longitude))
        }
        for endpoint in endpoints(points) {
            guard let json = await ask(endpoint, missing) else {
                continue
            }
            let answer = PlaceInfoLookup.match(json, to: missing)
            for (key, info) in answer {
                remember(key, info)
                found[key] = info
            }
            if !answer.isEmpty {
                report(answer)
            }
            var stillMissing: [Destination] = []
            for destination in missing {
                if answer[PlaceInfoLookup.key(destination)] == nil {
                    stillMissing.append(destination)
                }
            }
            // the Swiss server has only Switzerland and the land along its border: the others go to the next one
            if stillMissing.isEmpty || endpoint != OverpassEndpoints.switzerland {
                // asked and not in OpenStreetMap, or without opening hours there: nothing to say about it
                var none: [String: PlaceInfo] = [:]
                for destination in stillMissing {
                    let key = PlaceInfoLookup.key(destination)
                    remember(key, PlaceInfo())
                    none[key] = PlaceInfo()
                    found[key] = PlaceInfo()
                }
                if !none.isEmpty {
                    report(none)
                }
                break
            }
            missing = stillMissing
        }
        return found
    }

    /// Only Apple's points of interest are looked for: an address or a town has no opening hours.
    public nonisolated static func wants(_ destination: Destination) -> Bool {
        if destination.kind.isEmpty || destination.approximate {
            return false
        }
        if PlaceKinds.isArea(destination.kind) || PlaceKinds.isAddress(destination.kind) {
            return false
        }
        return !words(destination.name).isEmpty
    }

    /// The same name at the same place (to about a metre) is the same place.
    public nonisolated static func key(_ destination: Destination) -> String {
        let position = String(
            format: "%.5f,%.5f",
            locale: Locale(identifier: "en_US_POSIX"),
            destination.latitude,
            destination.longitude
        )
        return destination.name.lowercased() + "@" + position
    }

    /// Overpass QL: for each destination, the places with opening hours around it whose name is its name or the
    /// first words of it ("IKEA" for "IKEA Pratteln"); `match` then keeps those that are really it.
    nonisolated static func query(_ destinations: [Destination]) -> String {
        var query = "[out:json][timeout:5];("
        for destination in destinations {
            let nameWords = words(destination.name)
            if nameWords.isEmpty {
                continue
            }
            var names: [String] = []
            for count in 1...nameWords.count {
                names.append(nameWords[0..<count].joined(separator: " "))
            }
            let position = String(
                format: "%.4f,%.4f",
                locale: Locale(identifier: "en_US_POSIX"),
                destination.latitude,
                destination.longitude
            )
            query += "nwr(around:\(radiusMeters)," + position + ")[\"opening_hours\"][\"name\"~\"^(" + names.joined(separator: "|") + ")$\",i];"
        }
        query += ");out tags center;"
        return query
    }

    /// The info of the places in an Overpass answer, by the key of the destination each one is: of those whose
    /// name it has and that are close enough, the nearest. A destination with none is left out.
    nonisolated static func match(_ json: [String: Any], to destinations: [Destination]) -> [String: PlaceInfo] {
        var nearest: [String: (meters: Double, info: PlaceInfo)] = [:]
        guard let elements = json["elements"] as? [Any] else {
            return [:]
        }
        for item in elements {
            guard let element = item as? [String: Any] else {
                continue
            }
            // a node has its own position, a way or a relation the centre Overpass adds with "out center"
            var position = element
            if let elementCenter = element["center"] as? [String: Any] {
                position = elementCenter
            }
            guard let latitude = Json.double(position, "lat"), let longitude = Json.double(position, "lon") else {
                continue
            }
            let tags = element["tags"] as? [String: Any] ?? [:]
            let point = LatLng(latitude: latitude, longitude: longitude)
            var best: Destination?
            var bestMeters = Double.infinity
            for destination in destinations {
                if !isNamed(destination.name, by: tags) {
                    continue
                }
                let meters = RouteShaping.distanceMeters(point, LatLng(latitude: destination.latitude, longitude: destination.longitude))
                if meters <= matchMeters && meters < bestMeters {
                    best = destination
                    bestMeters = meters
                }
            }
            guard let destination = best else {
                continue
            }
            let destinationKey = PlaceInfoLookup.key(destination)
            if let earlier = nearest[destinationKey], earlier.meters <= bestMeters {
                continue
            }
            nearest[destinationKey] = (meters: bestMeters, info: PlaceInfo.fromTags(tags))
        }
        var found: [String: PlaceInfo] = [:]
        for (key, entry) in nearest {
            found[key] = entry.info
        }
        return found
    }

    /// True when the OpenStreetMap place with `tags` is called `name`, upper or lower case alike: by its name, its
    /// other name, or its name with its branch or town after it ("IKEA" in Pratteln is Apple's "IKEA Pratteln").
    nonisolated static func isNamed(_ name: String, by tags: [String: Any]) -> Bool {
        let wanted = words(name).joined(separator: " ")
        let osmName = words(Json.string(tags, "name")).joined(separator: " ")
        if wanted.isEmpty || osmName.isEmpty {
            return false
        }
        var names = [osmName, words(Json.string(tags, "alt_name")).joined(separator: " ")]
        for key in ["branch", "addr:city", "addr:place"] {
            let extra = words(Json.string(tags, key)).joined(separator: " ")
            if !extra.isEmpty {
                names.append(osmName + " " + extra)
            }
        }
        for candidate in names {
            if !candidate.isEmpty && candidate.compare(wanted, options: .caseInsensitive) == .orderedSame {
                return true
            }
        }
        return false
    }

    /// The words of `name` as the query writes them: what a regular expression reads as more than a character
    /// becomes "any character" (`isNamed` cleans both names the same way), so nothing in a name can end the
    /// query's string or change its expression.
    private nonisolated static func words(_ name: String) -> [String] {
        var cleaned = ""
        for scalar in name.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) {
                cleaned.append(" ")
            } else if #"\^$.|?*+()[]{}""#.unicodeScalars.contains(scalar) {
                cleaned.append(".")
            } else {
                cleaned.unicodeScalars.append(scalar)
            }
        }
        var found: [String] = []
        for word in cleaned.split(whereSeparator: { character in character.isWhitespace }) {
            if found.count >= maxWords {
                break
            }
            found.append(String(word))
        }
        return found
    }

    /// The answer of one server, or nil when it gave none.
    private func ask(_ endpoint: String, _ destinations: [Destination]) async -> [String: Any]? {
        let request = HttpRequest(
            method: "POST",
            url: endpoint,
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
            ],
            body: "data=" + OverpassPlaces.formEncode(PlaceInfoLookup.query(destinations)),
            timeoutSeconds: PlaceInfoLookup.serverTimeoutSeconds
        )
        let response: HttpResponse
        do {
            response = try await http.execute(request)
        } catch {
            return nil
        }
        if !response.isSuccessful() {
            return nil
        }
        guard let json = Json.parseObject(response.body) else {
            return nil
        }
        // out of time or memory: 200 with a remark
        if !Json.string(json, "remark").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return json
    }

    private func remembered(_ key: String) -> PlaceInfo? {
        guard let info = known[key] else {
            return nil
        }
        // used again: the last to go
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
        return info
    }

    private func remember(_ key: String, _ info: PlaceInfo) {
        if known[key] != nil, let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        known[key] = info
        order.append(key)
        while order.count > PlaceInfoLookup.maxKnown {
            let oldest = order.removeFirst()
            known.removeValue(forKey: oldest)
        }
    }
}
