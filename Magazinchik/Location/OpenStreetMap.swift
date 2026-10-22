import CoreLocation
import Foundation
import os

private let osmLogger = Logger(subsystem: "ru.magazinchik.app", category: "osm")

func osmLog(_ message: String) {
    print("Magazinchik OSM: \(message)")
    osmLogger.info("\(message, privacy: .public)")
}

/// Public OpenStreetMap lookups. One request at a time, with a User-Agent that names the app.
enum OpenStreetMap {
    static let userAgent = "Magazinchik/1.0 (iOS; discount-card wallet; https://github.com/Krelix1/magazinchik)"
    static let attribution = "© OpenStreetMap"

    /// Tried in order. overpass-api.de and kumi often time out; the French server is the one that answers.
    static let overpassEndpoints = [
        URL(string: "https://overpass.openstreetmap.fr/api/interpreter")!,
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.kumi.systems/api/interpreter")!
    ]

    private static let session = RequestGate()

    /// Network and JSON parsing leave the main actor. A city-wide Overpass reply is large enough to freeze taps if it is decoded there.
    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated) {
            try await work()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Case-folded prefix for an Overpass name regex. «Санта» → `^[Сс] *[Аа] *[Нн] *[Тт] *[Аа].*`
    /// so «Санта - 54» matches. Cyrillic is listed in both cases because Overpass `i` does not fold it.
    static func namePattern(for storeName: String) -> String? {
        let trimmed = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        var pieces: [String] = ["^"]
        var letters = 0
        for character in trimmed {
            guard character.isLetter || character.isNumber else { continue }
            if letters > 0 { pieces.append(" *") }
            pieces.append(characterClass(character))
            letters += 1
        }
        guard letters >= 2 else { return nil }
        pieces.append(".*")
        return pieces.joined()
    }

    static func overpassQuery(named storeName: String, near coordinate: CLLocationCoordinate2D, radius: CLLocationDistance) -> String? {
        guard let pattern = namePattern(for: storeName) else { return nil }
        let escaped = pattern
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let lat = format(coordinate.latitude)
        let lon = format(coordinate.longitude)
        let metres = Int(radius.rounded())
        let around = "(around:\(metres),\(lat),\(lon))"
        return """
        [out:json][timeout:25];
        (
          node["name"~"\(escaped)"]\(around);
          way["name"~"\(escaped)"]\(around);
          node["name:ru"~"\(escaped)"]\(around);
          way["name:ru"~"\(escaped)"]\(around);
        );
        out center tags;
        """
    }

    /// Nodes and ways whose name matches `storeName`, closest first, inside `radius`.
    /// Throws when every server fails. An empty array is a real reply with no matches — the caller must not cache it.
    static func nearbyPlaces(
        named storeName: String,
        near coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) async throws -> [PlaceDraft] {
        try await offMain {
            try await loadNearbyPlaces(named: storeName, near: coordinate, radius: radius)
        }
    }

    private static func loadNearbyPlaces(
        named storeName: String,
        near coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) async throws -> [PlaceDraft] {
        guard let query = overpassQuery(named: storeName, near: coordinate, radius: radius) else { return [] }
        var lastError: Error?
        var sawEmpty = false
        for endpoint in overpassEndpoints {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpBody = Data(query.utf8)
            request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            osmLog("request POST \(endpoint.absoluteString) store \(storeName) around \(format(coordinate.latitude)),\(format(coordinate.longitude)) radius \(Int(radius.rounded()))")
            do {
                let (data, status) = try await session.data(for: request)
                osmLog("response \(endpoint.host ?? endpoint.absoluteString) status \(status) bytes \(data.count)")
                let found = try places(matching: storeName, near: coordinate, radius: radius, overpassData: data)
                if found.isEmpty {
                    sawEmpty = true
                    osmLog("response \(endpoint.host ?? endpoint.absoluteString) status \(status) matched 0")
                    continue
                }
                let origin = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                for place in found.prefix(5) {
                    let metres = origin.distance(to: GeoPoint(latitude: place.latitude, longitude: place.longitude))
                    osmLog("match \(place.name) \(Int(metres.rounded())) m at \(format(place.latitude)),\(format(place.longitude))")
                }
                return found
            } catch {
                lastError = error
                osmLog("response \(endpoint.host ?? endpoint.absoluteString) failed \(error)")
            }
        }
        if sawEmpty, lastError == nil {
            return []
        }
        throw lastError ?? OpenStreetMapError.unavailable(status: 0, detail: "OpenStreetMap не ответил")
    }

    /// Stores whose name starts with `brand`, inside the city's box, closest to the city centre first.
    /// An empty array is a real empty reply and must not be cached. A failure throws.
    static func stores(named brand: String, in box: BoundingBox, around center: CLLocationCoordinate2D) async throws -> [PlaceDraft] {
        try await offMain {
            try await loadStores(named: brand, in: box, around: center)
        }
    }

    private static func loadStores(named brand: String, in box: BoundingBox, around center: CLLocationCoordinate2D) async throws -> [PlaceDraft] {
        guard let query = overpassQuery(named: brand, in: box) else { return [] }
        var lastError: Error?
        var sawEmpty = false
        for endpoint in overpassEndpoints {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpBody = Data(query.utf8)
            request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            osmLog("request POST \(endpoint.absoluteString) brand \(brand) bbox \(format(box.minLatitude)),\(format(box.minLongitude)),\(format(box.maxLatitude)),\(format(box.maxLongitude))")
            do {
                let (data, status) = try await session.data(for: request)
                osmLog("response \(endpoint.host ?? endpoint.absoluteString) status \(status) bytes \(data.count)")
                let found = try places(matching: brand, in: box, around: center, overpassData: data)
                if found.isEmpty {
                    sawEmpty = true
                    continue
                }
                return found
            } catch {
                lastError = error
                osmLog("response \(endpoint.host ?? endpoint.absoluteString) failed \(error)")
            }
        }
        if sawEmpty, lastError == nil { return [] }
        throw lastError ?? OpenStreetMapError.unavailable(status: 0, detail: "OpenStreetMap не ответил")
    }

    static func overpassQuery(named storeName: String, in box: BoundingBox) -> String? {
        guard let pattern = namePattern(for: storeName) else { return nil }
        let escaped = pattern
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let south = format(box.minLatitude)
        let west = format(box.minLongitude)
        let north = format(box.maxLatitude)
        let east = format(box.maxLongitude)
        let area = "(\(south),\(west),\(north),\(east))"
        return """
        [out:json][timeout:25];
        (
          node["name"~"\(escaped)"]\(area);
          way["name"~"\(escaped)"]\(area);
          node["name:ru"~"\(escaped)"]\(area);
          way["name:ru"~"\(escaped)"]\(area);
        );
        out center tags;
        """
    }

    /// Settlements for the city picker. The saved value is the centre and the bounding box, not the name alone.
    static func searchCities(_ query: String) async throws -> [CityMatch] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return [] }
        return try await offMain {
            try await loadCities(text)
        }
    }

    private static func loadCities(_ text: String) async throws -> [CityMatch] {
        guard text.count >= 2 else { return [] }
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "6"),
            URLQueryItem(name: "q", value: text)
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("ru,en", forHTTPHeaderField: "Accept-Language")
        osmLog("request GET \(components.url?.absoluteString ?? "")")
        let (data, status) = try await session.data(for: request)
        osmLog("response nominatim status \(status) bytes \(data.count)")
        let decoded = try JSONDecoder().decode([NominatimArea].self, from: data)
        return decoded.compactMap(\.city)
    }

    static func places(matching storeName: String, in box: BoundingBox, around center: CLLocationCoordinate2D, overpassData data: Data) throws -> [PlaceDraft] {
        let found = try places(matching: storeName, near: center, radius: .greatestFiniteMagnitude, overpassData: data)
        let origin = GeoPoint(latitude: center.latitude, longitude: center.longitude)
        return found
            .filter { box.contains(latitude: $0.latitude, longitude: $0.longitude) }
            .sorted { origin.distance(to: GeoPoint(latitude: $0.latitude, longitude: $0.longitude)) < origin.distance(to: GeoPoint(latitude: $1.latitude, longitude: $1.longitude)) }
    }

    /// One Nominatim search for a typed address. Throws on failure; never more than one OSM request at a time.
    static func geocode(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [PlaceDraft] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return [] }
        return try await offMain {
            try await loadGeocode(text, near: coordinate)
        }
    }

    private static func loadGeocode(_ text: String, near coordinate: CLLocationCoordinate2D?) async throws -> [PlaceDraft] {
        guard text.count >= 2 else { return [] }
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        var items = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "q", value: text)
        ]
        if let coordinate {
            let latPad = 0.18
            let lonPad = 0.28
            let viewbox = [
                format(coordinate.longitude - lonPad),
                format(coordinate.latitude + latPad),
                format(coordinate.longitude + lonPad),
                format(coordinate.latitude - latPad)
            ].joined(separator: ",")
            items.append(URLQueryItem(name: "viewbox", value: viewbox))
            items.append(URLQueryItem(name: "bounded", value: "0"))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue("ru,en", forHTTPHeaderField: "Accept-Language")
        osmLog("request GET \(components.url?.absoluteString ?? "")")
        let (data, status) = try await session.data(for: request)
        osmLog("response nominatim status \(status) bytes \(data.count)")
        let decoded = try JSONDecoder().decode([NominatimPlace].self, from: data)
        return decoded.compactMap { $0.place }
    }

    static func places(
        matching storeName: String,
        near coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        overpassData data: Data
    ) throws -> [PlaceDraft] {
        let envelope = try JSONDecoder().decode(OverpassEnvelope.self, from: data)
        if envelope.elements == nil || (envelope.elements?.isEmpty == true && envelope.remark?.isEmpty == false) {
            throw OpenStreetMapError.unavailable(status: 200, detail: envelope.remark ?? "OpenStreetMap не ответил")
        }
        guard let elements = envelope.elements else {
            throw OpenStreetMapError.unavailable(status: 200, detail: "OpenStreetMap не ответил")
        }
        let origin = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var seen = Set<String>()
        var matches: [(place: PlaceDraft, distance: Double)] = []
        for element in elements {
            guard let place = element.place(matching: storeName) else { continue }
            let distance = origin.distance(to: GeoPoint(latitude: place.latitude, longitude: place.longitude))
            guard distance <= radius + 50 else { continue }
            let key = "\(Int(place.latitude * 10_000)),\(Int(place.longitude * 10_000)),\(CardText.normalizedName(place.name))"
            guard seen.insert(key).inserted else { continue }
            matches.append((place, distance))
        }
        return matches.sorted { $0.distance < $1.distance }.map(\.place)
    }

    private static func characterClass(_ character: Character) -> String {
        let variants = caseVariants(of: character).map(escapeInClass).joined()
        return "[\(variants)]"
    }

    private static func caseVariants(of character: Character) -> [Character] {
        let source = String(character)
        let locale = Locale(identifier: "ru_RU")
        var variants = Set((source.lowercased(with: locale) + source.uppercased(with: locale)).map { $0 })
        if variants.contains(where: { "еЕёЁ".contains($0) }) {
            variants.formUnion(["е", "Е", "ё", "Ё"])
        }
        return variants.sorted()
    }

    private static func escapeInClass(_ character: Character) -> String {
        switch character {
        case "\\", "]", "^", "-": return "\\\(character)"
        default: return String(character)
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

enum OpenStreetMapError: Error, CustomStringConvertible {
    case unavailable(status: Int, detail: String)

    var description: String {
        switch self {
        case .unavailable(let status, let detail):
            return "status \(status): \(detail)"
        }
    }
}

private actor RequestGate {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": OpenStreetMap.userAgent]
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    private var lastStart = Date.distantPast

    private var busy = false

    /// The public servers allow only light use: one request in flight, and at least a second between starts.
    /// Cancelling the caller cancels the socket, so a timeout cannot sit on the main actor or block the next search.
    func data(for request: URLRequest) async throws -> (Data, Int) {
        while busy {
            try await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
        }
        busy = true
        defer { busy = false }

        let wait = 1.1 - Date().timeIntervalSince(lastStart)
        if wait > 0 {
            try await Task.sleep(for: .seconds(wait))
        }
        try Task.checkCancellation()
        lastStart = .now
        let session = self.session
        let (data, response) = try await Self.load(session: session, request: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenStreetMapError.unavailable(status: 0, detail: "OpenStreetMap не ответил")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenStreetMapError.unavailable(status: http.statusCode, detail: "HTTP \(http.statusCode)")
        }
        return (data, http.statusCode)
    }

    /// Runs the transfer off the caller's actor and stops it when that caller is cancelled.
    private static func load(session: URLSession, request: URLRequest) async throws -> (Data, URLResponse) {
        let ticket = RequestTicket()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let response else {
                        continuation.resume(throwing: OpenStreetMapError.unavailable(status: 0, detail: "OpenStreetMap не ответил"))
                        return
                    }
                    continuation.resume(returning: (data ?? Data(), response))
                }
                ticket.begin(task)
            }
        } onCancel: {
            ticket.cancel()
        }
    }
}

/// Holds the in-flight transfer so a cancelled search can close it before the timeout.
private final class RequestTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    func begin(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let cancelled = self.cancelled
        lock.unlock()
        if cancelled {
            task.cancel()
        } else {
            task.resume()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

private struct OverpassEnvelope: Decodable {
    var elements: [OverpassElement]?
    var remark: String?
}

private struct OverpassElement: Decodable {
    var type: String
    var lat: Double?
    var lon: Double?
    var center: Center?
    var tags: [String: String]?

    struct Center: Decodable {
        var lat: Double
        var lon: Double
    }

    func place(matching storeName: String) -> PlaceDraft? {
        guard type == "node" || type == "way" else { return nil }
        let latitude = lat ?? center?.lat
        let longitude = lon ?? center?.lon
        guard let latitude, let longitude, let tags else { return nil }
        let names = [tags["name"], tags["name:ru"]].compactMap { $0 }
        guard let name = names.first(where: { CardText.place($0, matchesBrand: storeName) }) else { return nil }
        return PlaceDraft(name: name, address: Self.address(from: tags), latitude: latitude, longitude: longitude)
    }

    /// Street and house number only. A store with no street keeps an empty subtitle.
    private static func address(from tags: [String: String]) -> String {
        let street = tags["addr:street"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !street.isEmpty else { return "" }
        let number = tags["addr:housenumber"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !number.isEmpty else { return street }
        return "\(street), \(number)"
    }
}

private struct NominatimArea: Decodable {
    var lat: String
    var lon: String
    var displayName: String
    var boundingbox: [String]?

    enum CodingKeys: String, CodingKey {
        case lat, lon
        case displayName = "display_name"
        case boundingbox
    }

    var city: CityMatch? {
        guard let latitude = Double(lat), let longitude = Double(lon), let boundingbox, boundingbox.count == 4 else { return nil }
        guard let south = Double(boundingbox[0]), let north = Double(boundingbox[1]), let west = Double(boundingbox[2]), let east = Double(boundingbox[3]) else { return nil }
        let parts = displayName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let name = parts.first ?? displayName
        let detail = parts.dropFirst().joined(separator: ", ")
        return CityMatch(
            name: name,
            detail: detail,
            latitude: latitude,
            longitude: longitude,
            box: BoundingBox(minLatitude: min(south, north), maxLatitude: max(south, north), minLongitude: min(west, east), maxLongitude: max(west, east))
        )
    }
}

private struct NominatimPlace: Decodable {
    var lat: String
    var lon: String
    var name: String?
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case lat, lon, name
        case displayName = "display_name"
    }

    var place: PlaceDraft? {
        guard let latitude = Double(lat), let longitude = Double(lon) else { return nil }
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = displayName.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? displayName
        return PlaceDraft(
            name: (title?.isEmpty == false ? title! : fallback),
            address: displayName,
            latitude: latitude,
            longitude: longitude
        )
    }
}
