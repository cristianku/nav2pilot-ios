import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct ParkingFeeds {
    typealias Row = [String: Any]
    typealias Garage = BaselParking.Garage
    enum City: String { case basel, zurich, stgallen, nantes, italy, verona, asheville, hongkong, singapore, germany }
    let city: City, lat: Int, lon: Int
    var key: String { "\(city.rawValue):\(lat):\(lon)" }
    static let hkInfo = "https://api.data.gov.hk/v1/carpark-info-vacancy?data=info&vehicleTypes=privateCar&lang=en_US"
    private static let regions: [(City, Double, Double, Double, Double)] = [
        (.verona,45.38,10.92,45.49,11.06),
        (.basel,47.52,7.55,47.59,7.63), (.zurich,47.30,8.44,47.45,8.64), (.stgallen,47.37,9.27,47.48,9.46),
        (.nantes,47.10,-1.76,47.35,-1.40), (.italy,46.19,10.35,47.10,12.52), (.asheville,35.54,-82.62,35.65,-82.48),
        (.hongkong,22.14,113.82,22.57,114.45), (.singapore,1.20,103.60,1.48,104.10), (.germany,47.27,5.86,55.06,15.05)
    ]
    static func covering(_ area: MapArea) -> [Self] {
        var result: [Self] = []
        for (c,s,w,n,e) in regions where area.south <= n && area.north >= s && area.west <= e && area.east >= w {
            if c != .germany { result.append(Self(city:c,lat:0,lon:0)); continue }
            for y in Int(floor(max(s,area.south)))...Int(floor(min(n,area.north))) {
                for x in Int(floor(max(w,area.west)))...Int(floor(min(e,area.east))) { result.append(Self(city:c,lat:y,lon:x)) }
            }
        }
        return result
    }
    static func get(_ http: HttpClient, _ url: String) async throws -> HttpResponse {
        let r = try await http.execute(HttpRequest(method:"GET",url:url,timeoutSeconds:5))
        guard r.isSuccessful() else { throw HttpClientError("Parking data unavailable") }
        return r
    }
    static func rows(_ r: HttpResponse, _ key: String) throws -> [Row] {
        guard let rows = Json.parseObject(r.body)?[key] as? [Row] else { throw HttpClientError("Invalid parking feed") }
        return rows
    }
    static func directory(_ name: String) -> [String:[Any]] {
        guard let url = Bundle.module.url(forResource:name,withExtension:"json"), let d = try? Data(contentsOf:url),
              let json = try? JSONSerialization.jsonObject(with:d) as? [String:[Any]] else { return [:] }
        return json
    }
    private static let sg = directory("singapore"), zh = directory("zurich")
    private static let vr = directory("verona")
    func load(_ http: HttpClient, directoryHK: () async throws -> [Row]) async throws -> [Garage] {
        let iso = ISO8601DateFormatter()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"en_US_POSIX")
        func format(_ pattern: String, _ zone: String) { formatter.dateFormat = pattern; formatter.timeZone = TimeZone(identifier:zone) }
        func rows(_ url: String, _ key: String) async throws -> [Row] { try Self.rows(await Self.get(http,url),key) }
        func text(_ r: Row, _ k: String) -> String { Json.string(r,k).trimmingCharacters(in:.whitespacesAndNewlines) }
        func int(_ r: Row, _ k: String) -> Int? { Int(text(r,k)) }
        func g(_ source:String, _ zone:String, _ id:String, _ name:String, _ address:String, _ lat:Double?, _ lon:Double?,
               _ at:Date?, _ status:String, _ free:Int?, _ total:Int?, _ age:Double = 900) -> Garage? {
            guard !id.isEmpty, !name.isEmpty, let lat, let lon, CoordinateRules.isValid(latitude:lat,longitude:lon) else { return nil }
            return Garage(id:source+":"+id,title:name,address:address,source:source,zone:zone,published:at ?? .distantPast,
                          point:LatLng(latitude:lat,longitude:lon),status:status.lowercased(),free:free,total:total,age:age)
        }
        switch city {
        case .verona:
            return try await rows("https://api.amt3.it/", "Numeri Parcheggi").compactMap { r in
                let id = text(r,"id")
                guard let d = Self.vr[id], d.count == 3 else { return nil }
                let at = Int64(text(r,"ts")).flatMap { (1...4102444800).contains($0) ? Date(timeIntervalSince1970: Double($0)) : nil }
                let total = int(r,"posti_totali"), occupied = int(r,"parkingNumberOfOccupiedSpaces")
                let free = int(r,"posti_liberi").flatMap { n -> Int? in
                    guard let total, total > 0, (0...total).contains(n),
                          Json.isNull(r,"parkingNumberOfOccupiedSpaces") || occupied == total - n else { return nil }
                    return n
                }
                return g("AMT3 Verona", "Europe/Rome", id, text(r,"parcheggio"), d[2] as? String ?? "",
                         d[0] as? Double, d[1] as? Double, at, "open", free, total, 300)
            }
        case .basel, .stgallen, .nantes:
            let fields: (String,String,String,String,String,String,String,String,String,String)
            switch city {
            case .basel: fields = ("data.bs.ch","100088","geo_point_2d","title","published","status","free","total","id","Parkhäuser Basel-Stadt")
            case .stgallen: fields = ("daten.stadt.sg.ch","freie-parkplatze-in-der-stadt-stgallen-pls","koordinaten","ph_name","letzte_aktualisierung","ph_status","frei","anzahl_parkplatze","ph_id","Stadt St.Gallen · PLS")
            default: fields = ("data.nantesmetropole.fr","244400404_parkings-publics-nantes-disponibilites","location","grp_nom","grp_horodatage","grp_statut","grp_disponible","grp_exploitation","grp_identifiant","Nantes Métropole")
            }
            let (host,dataset,geo,name,time,state,free,total,id,source) = fields
            return try await rows("https://\(host)/api/explore/v2.1/catalog/datasets/\(dataset)/records?limit=100","results").compactMap { r in
                let p = r[geo] as? Row ?? [:], s = text(r,state)
                let status = city == .nantes ? (s == "5" ? "open" : ["1","2"].contains(s) ? "closed" : "") : s
                return g(source, city == .nantes ? "Europe/Paris" : "Europe/Zurich",
                         text(r,id).isEmpty ? text(r,"name") : text(r,id), text(r,name), text(r,city == .nantes ? "adresse":"address"),
                         p["lat"] as? Double,p["lon"] as? Double,iso.date(from:text(r,time)),status,int(r,free),int(r,total),city == .basel ? 300:900)
            }
        case .italy:
            format("yyyy-MM-dd HH:mm:ss.SSSZ","Europe/Rome")
            return try await rows("https://mobility.api.opendatahub.com/v2/flat,node/ParkingStation/free/latest?limit=5000&select=scode,sname,sorigin,scoordinate,smetadata.capacity,mvalue,mvalidtime","data").compactMap { r in
                guard let p = r["scoordinate"] as? Row,int(p,"srid") == 4326 else { return nil }
                return g("Open Data Hub · "+text(r,"sorigin"),"Europe/Rome",text(r,"scode"),text(r,"sname"),"",p["y"] as? Double,p["x"] as? Double,
                         formatter.date(from:text(r,"mvalidtime")),"open",int(r,"mvalue"),int(r,"smetadata.capacity"))
            }
        case .asheville:
            format("EEE, dd MMM yyyy HH:mm:ss zzz","GMT")
            let r = try await Self.get(http,"https://s3.amazonaws.com/avl-parking-decks/all-spaces.json")
            let at = r.header("Last-Modified").flatMap(formatter.date)
            return try Self.rows(r,"decks").compactMap { d in
                guard let p = d["coords"] as? [Double], p.count == 2 else { return nil }
                return g("City of Asheville","America/New_York",text(d,"slug"),text(d,"name"),text(d,"address"),p[0],p[1],at,
                         text(d,"available") == "closed" ? "closed":"open",int(d,"available"),nil,300)
            }
        case .zurich:
            format("EEE, dd MMM yyyy HH:mm:ss zzz","GMT")
            let rss = try await Self.get(http,"https://www.pls-zh.ch/plsFeed/rss").body
            return try ZurichRSS.read(rss).compactMap { r in
                guard let id = URLComponents(string:r["guid"] ?? "")?.queryItems?.first(where:{$0.name == "pid"})?.value,
                      let d = Self.zh[id], d.count == 4 else { return nil }
                let values = (r["description"] ?? "").components(separatedBy:"/").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
                return g("Parkleitsystem Stadt Zürich","Europe/Zurich",id,(r["title"] ?? "").components(separatedBy:" /")[0],
                         d[2] as? String ?? "",d[0] as? Double,d[1] as? Double,formatter.date(from:r["pubDate"] ?? ""),
                         values[0],values.count == 2 ? Int(values[1]) : nil,(d[3] as? Int).flatMap { $0 > 0 ? $0:nil })
            }
        case .singapore:
            format("yyyy-MM-dd'T'HH:mm:ss","Asia/Singapore")
            let data = try await rows("https://api.data.gov.sg/v1/transport/carpark-availability","items").last?["carpark_data"] as? [Row] ?? []
            return data.compactMap { r in
                let id = text(r,"carpark_number")
                guard let d = Self.sg[id], d.count == 3, let lots = r["carpark_info"] as? [Row] else { return nil }
                let cars = lots.filter { text($0,"lot_type") == "C" }
                guard cars.count == 1 else { return nil }
                return g("HDB · data.gov.sg","Asia/Singapore",id,"HDB "+id,d[2] as? String ?? "",d[0] as? Double,d[1] as? Double,
                         formatter.date(from:text(r,"update_datetime")),"open",int(cars[0],"lots_available"),int(cars[0],"total_lots"),300)
            }
        case .hongkong:
            format("yyyy-MM-dd HH:mm:ss","Asia/Hong_Kong")
            let sites = try await directoryHK()
            let live = try await rows("https://api.data.gov.hk/v1/carpark-info-vacancy?data=vacancy&vehicleTypes=privateCar","results")
            let indexed = Dictionary(live.map { (text($0,"park_Id"), $0) }, uniquingKeysWith: { a,_ in a })
            return sites.compactMap { r in
                let id = text(r,"park_Id"), data = indexed[id]?["privateCar"] as? [Row], cars = r["privateCar"] as? Row
                guard data != nil || cars != nil else { return nil }
                let v = data?.count == 1 ? data![0] : [:]
                return g("Hong Kong Transport Department","Asia/Hong_Kong",id,text(r,"name"),text(r,"displayAddress"),
                         r["latitude"] as? Double,r["longitude"] as? Double,formatter.date(from:text(v,"lastupdate")),
                         text(r,"opening_status"),text(v,"vacancy_type") == "A" ? int(v,"vacancy"):nil,cars.flatMap { int($0,"space") })
            }
        case .germany:
            let url = "https://api.mobidata-bw.de/park-api/api/public/v3/parking-sites?purpose=CAR&ignore_duplicates=true&lat_min=\(lat)&lon_min=\(lon)&lat_max=\(lat+1)&lon_max=\(lon+1)&limit=500&realtime_data_updated_at_since=" + iso.string(from:Date().addingTimeInterval(-900))
            var result: [Garage] = [], cursor = -1
            repeat {
                let page = try await Self.get(http,url + (cursor < 0 ? "" : "&start=\(cursor)"))
                result += try Self.rows(page,"items").compactMap { r in
                    guard r["has_realtime_data"] as? Bool == true, text(r,"purpose") == "CAR" else { return nil }
                    let s = text(r,"realtime_opening_status")
                    return g("MobiData BW · "+text(r,"operator_name"),"Europe/Berlin",text(r,"id"),text(r,"name"),text(r,"address"),
                             r["lat"] as? Double,r["lon"] as? Double,iso.date(from:text(r,"realtime_data_updated_at")),s.isEmpty ? "open":s,
                             int(r,"realtime_free_capacity"),int(r,"realtime_capacity") ?? int(r,"capacity"))
                }
                guard let next = Json.parseObject(page.body)?["next_id"] as? Int, next > cursor else { break }
                cursor = next
            } while !Task.isCancelled
            return result
        }
    }
}

private final class ZurichRSS: NSObject, XMLParserDelegate {
    var rows: [[String:String]] = [], item: [String:String]?, value = ""
    static func read(_ text: String) throws -> [[String:String]] {
        guard !text.localizedCaseInsensitiveContains("<!DOCTYPE") else { throw HttpClientError("Invalid RSS feed") }
        let reader = ZurichRSS(), parser = XMLParser(data:Data(text.utf8))
        parser.delegate = reader; parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw HttpClientError("Invalid parking RSS") }
        return reader.rows
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
        if elementName == "item" { item = [:] }
        value = ""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { value += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "item", let item { rows.append(item); self.item = nil }
        else { item?[elementName] = value.trimmingCharacters(in:.whitespacesAndNewlines) }
    }
}
