import Foundation

public struct VenuePhoto {
    public let thumbnail, page: URL
    public let credit, license: String
}
public struct VenueReview: Equatable {
    public let text, author: String
    public let stars: Double?
}
public enum PlaceDetails {
    private static let client = URLSessionHttpClient(userAgent:"Nav2Pilot iOS (https://github.com/cristianku/nav2pilot-ios)")
    private static func escape(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? "" }
    private static func json(_ url: String) async throws -> [String:Any] {
        let r = try await client.execute(HttpRequest(method:"GET",url:url,timeoutSeconds:6))
        guard r.isSuccessful(), let data = Json.parseObject(r.body) else { throw HttpClientError("Place details unavailable") }
        return data
    }
    public static func tags(_ place: Place) async -> PlaceInfo? {
        if let info = place.info { return info }
        guard place.osmID.range(of:"^(node|way|relation)/[1-9][0-9]{0,17}$",options:.regularExpression) != nil else { return nil }
        let bits = place.osmID.components(separatedBy:"/")
        let q = "[out:json][timeout:5];\(bits[0])(\(bits[1]));out tags;"
        let urls = OverpassEndpoints.forPoints([LatLng(latitude:place.latitude,longitude:place.longitude)])
        for url in urls {
            guard !Task.isCancelled else { break }
            if let r = try? await client.execute(HttpRequest(method:"POST",url:url,headers:["Content-Type":"application/x-www-form-urlencoded"],
                body:"data="+escape(q),timeoutSeconds:6)), r.isSuccessful(),
               let rows = Json.parseObject(r.body)?["elements"] as? [[String:Any]],
               let item = rows.first(where:{ Json.string($0,"type")+"/"+Json.string($0,"id") == place.osmID }),
               let tags = item["tags"] as? [String:Any] { return PlaceInfo.fromTags(tags) }
        }
        return nil
    }
    public static func photo(_ info: PlaceInfo) async throws -> VenuePhoto? {
        var file = info.commonsFile
        if file.isEmpty, info.wikidata.range(of:"^Q[1-9][0-9]{0,12}$",options:.regularExpression) != nil {
            let data = try await json("https://www.wikidata.org/w/api.php?action=wbgetclaims&format=json&property=P18&entity="+info.wikidata)
            let claims = (data["claims"] as? [String:Any])?["P18"] as? [[String:Any]] ?? []
            file = claims.filter { ($0["rank"] as? String) != "deprecated" }.compactMap {
                (($0["mainsnak"] as? [String:Any])?["datavalue"] as? [String:Any])?["value"] as? String
            }.first ?? ""
        }
        guard file.count <= 250, !file.contains("|"), ["jpg","jpeg","png","webp"].contains((file as NSString).pathExtension.lowercased()) else { return nil }
        let data = try await json("https://commons.wikimedia.org/w/api.php?action=query&format=json&formatversion=2&prop=imageinfo&iiurlwidth=500&iiprop=url%7Cextmetadata&iiextmetadatafilter=Artist%7CAttribution%7CLicenseShortName&titles="+escape("File:"+file))
        let pages = (data["query"] as? [String:Any])?["pages"] as? [[String:Any]]
        guard let row = (pages?.first?["imageinfo"] as? [[String:Any]])?.first, let m = row["extmetadata"] as? [String:[String:Any]],
              let thumb = URL(string:Json.string(row,"thumburl")), thumb.scheme == "https", ["upload.wikimedia.org","thumb.wikimedia.org"].contains(thumb.host ?? ""),
              let page = URL(string:Json.string(row,"descriptionurl")), page.scheme == "https", page.host == "commons.wikimedia.org",
              let credit = (m["Attribution"]?["value"] ?? m["Artist"]?["value"]) as? String, !credit.isEmpty,
              let license = m["LicenseShortName"]?["value"] as? String, !license.isEmpty else { return nil }
        return VenuePhoto(thumbnail:thumb,page:page,credit:credit.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression)
            .replacingOccurrences(of:"&amp;",with:"&"),license:license)
    }
    public static func reviews(_ place: Place) async throws -> [VenueReview] {
        guard !place.name.isEmpty, place.name != place.category.singular, !place.osmID.isEmpty || place.garage != nil else { return [] }
        let sub = "geo:\(place.latitude),\(place.longitude)?u=35&q=" + escape(place.name)
        return parseReviews(try await json("https://api.mangrove.reviews/reviews?opinionated=true&limit=8&sub="+escape(sub)), place)
    }
    static func parseReviews(_ data: [String:Any], _ place: Place) -> [VenueReview] {
        let rows = data["reviews"] as? [[String:Any]] ?? []
        return Array(rows.compactMap { row -> VenueReview? in
            guard let p = row["payload"] as? [String:Any], let u = URLComponents(string:Json.string(p,"sub")), u.scheme == "geo" else { return nil }
            let xy = u.path.prefix { $0 != ";" }.split(separator:",")
            guard xy.count == 2, let lat = Double(xy[0]), let lon = Double(xy[1]), CoordinateRules.isValid(latitude:lat,longitude:lon),
                  RouteShaping.distanceMeters(LatLng(latitude:lat,longitude:lon),LatLng(latitude:place.latitude,longitude:place.longitude)) <= 100 else { return nil }
            let meta = p["metadata"] as? [String:Any] ?? [:], id = Json.string(meta,"osm_id").split(separator:"/").prefix(2).joined(separator:"/")
            if !id.isEmpty && !place.osmID.isEmpty { guard id == place.osmID else { return nil } }
            else { guard let q = u.queryItems?.first(where:{$0.name == "q"})?.value, q.caseInsensitiveCompare(place.name) == .orderedSame else { return nil } }
            let text = Json.string(p,"opinion").trimmingCharacters(in:.whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return VenueReview(text:String(text.prefix(1500)),author:String(Json.string(meta,"nickname").prefix(80)),
                              stars:(p["rating"] as? Int).flatMap { (0...100).contains($0) ? Double($0)/20:nil })
        }.prefix(3))
    }
}
