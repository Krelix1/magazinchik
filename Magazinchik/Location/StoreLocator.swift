import CoreLocation
import SwiftData

/// A store address picked by the person or found on the map, before it's saved to a card.
struct PlaceDraft: Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    init(name: String, address: String = "", latitude: Double, longitude: Double) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ location: StoreLocation) {
        self.init(name: location.name, address: location.address, latitude: location.latitude, longitude: location.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func makeLocation(isUserDefined: Bool) -> StoreLocation {
        StoreLocation(name: name, address: address, latitude: latitude, longitude: longitude, isUserDefined: isUserDefined)
    }
}

/// Order for a typed store query. Names that start with the query come first, closest first.
/// A tighter string farther away does not jump ahead of a nearby store.
enum PlaceOrdering {
    /// Wide enough to include a store 7 km away, and small enough that the public Overpass servers still answer.
    /// A 25 km query times out, which used to leave the search list empty.
    static let pickerRadius: CLLocationDistance = 12_000
    static let resultLimit = 15

    static func ordered(_ places: [PlaceDraft], query: String, near origin: GeoPoint, limit: Int = resultLimit) -> [PlaceDraft] {
        let queryName = CardText.normalizedName(query)
        guard queryName.count >= 2 else { return Array(places.prefix(limit)) }

        struct Candidate {
            var place: PlaceDraft
            var distance: Double
            var nameStartsWithQuery: Bool
        }

        var closest: [String: Candidate] = [:]
        for place in places {
            let normalized = CardText.normalizedName(place.name)
            guard !normalized.isEmpty else { continue }
            let distance = origin.distance(to: GeoPoint(latitude: place.latitude, longitude: place.longitude))
            let candidate = Candidate(
                place: place,
                distance: distance,
                nameStartsWithQuery: normalized.hasPrefix(queryName)
            )
            if let existing = closest[normalized], existing.distance <= distance { continue }
            closest[normalized] = candidate
        }

        let prefixMatches = closest.values.filter(\.nameStartsWithQuery).sorted { $0.distance < $1.distance }
        let others = closest.values.filter { !$0.nameStartsWithQuery }.sorted { $0.distance < $1.distance }
        return (prefixMatches + others).prefix(limit).map(\.place)
    }
}

struct StoreLookupJob: Sendable {
    var cardID: UUID
    var query: String
}

struct StoreLookupResult: Sendable {
    var cardID: UUID
    var query: String
    var places: [PlaceDraft]
}

/// Typed search: nearby store names and address hits together.
/// A failed or empty nearby lookup is `nearby == nil` or `[]` and does not drop `addresses`.
enum PlaceSearch {
    static func results(
        query: String,
        near origin: GeoPoint?,
        nearby: [PlaceDraft]?,
        addresses: [PlaceDraft]
    ) -> [PlaceDraft] {
        let combined = (nearby ?? []) + addresses
        guard let origin else { return Array(combined.prefix(PlaceOrdering.resultLimit)) }
        return PlaceOrdering.ordered(combined, query: query, near: origin)
    }
}

@MainActor
enum StoreLocator {
    static let searchRadius: CLLocationDistance = 5_000
    static let refreshDistance: CLLocationDistance = 2_000
    static let maxAge: TimeInterval = 7 * 24 * 3600
    static let maxStoresPerCard = 15

    /// `force` skips the saved time and distance. The location button does not pass it: a press ranks the cache first and only looks up stores in the background when this is already true.
    static func needsRefresh(_ card: LoyaltyCard, near location: CLLocation, now: Date = .now, force: Bool = false) -> Bool {
        guard card.findsStoresAutomatically, !card.searchQuery.isEmpty else { return false }
        if force { return true }
        guard let date = card.storesSearchedAt,
              let latitude = card.storesSearchLatitude,
              let longitude = card.storesSearchLongitude else { return true }
        if now.timeIntervalSince(date) > maxAge { return true }
        return location.distance(from: CLLocation(latitude: latitude, longitude: longitude)) > refreshDistance
    }

    /// One lookup at a time, in the order they were asked for. A later forced check still runs after the one already going.
    private static var tail: Task<Void, Never>?

    /// Finds stores named like the card around `location`.
    /// Uses the saved matches unless they are missing, older than about 7 days, or from more than about 2 km away.
    /// `force` is the manual control: it asks again even when the cache is fresh.
    /// The network call runs off the main actor. A failed or empty lookup keeps the points already saved and is not remembered as “nothing nearby”.
    static func refresh(_ cards: [LoyaltyCard], near location: CLLocation, in context: ModelContext, force: Bool = false) async {
        let previous = tail
        let next = Task { @MainActor in
            await previous?.value
            await perform(cards, near: location, in: context, force: force)
        }
        tail = next
        await next.value
    }

    private static func perform(_ cards: [LoyaltyCard], near location: CLLocation, in context: ModelContext, force: Bool) async {
        let jobs = cards.compactMap { card -> StoreLookupJob? in
            guard needsRefresh(card, near: location, force: force) else { return nil }
            return StoreLookupJob(cardID: card.id, query: card.searchQuery)
        }
        guard !jobs.isEmpty else { return }
        osmLog(String(format: "device %.6f, %.6f accuracy %.0f m", location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy))
        let coordinate = location.coordinate
        let fetched = await fetchStores(jobs, near: coordinate, radius: searchRadius)
        for item in fetched {
            guard let card = cards.first(where: { $0.id == item.cardID }),
                  !card.isDeleted,
                  card.searchQuery == item.query else { continue }
            apply(matches: item.places, to: card, near: location, in: context)
        }
        if !fetched.isEmpty {
            try? context.save()
        }
    }

    /// OpenStreetMap work for the cards that need it. Not isolated to the main actor, so a slow reply cannot freeze taps or typing.
    nonisolated static func fetchStores(
        _ jobs: [StoreLookupJob],
        near coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) async -> [StoreLookupResult] {
        var fetched: [StoreLookupResult] = []
        for job in jobs {
            if Task.isCancelled { break }
            do {
                let places = try await OpenStreetMap.nearbyPlaces(
                    named: job.query,
                    near: coordinate,
                    radius: radius
                )
                fetched.append(StoreLookupResult(cardID: job.cardID, query: job.query, places: places))
            } catch {
                osmLog("lookup failed for \(job.query), cache kept (\(error))")
            }
        }
        return fetched
    }

    /// Writes a non-empty OpenStreetMap result onto the card. Empty matches are ignored so a timeout cannot stick.
    /// Pins the person set themselves are left in place.
    static func apply(matches: [PlaceDraft], to card: LoyaltyCard, near location: CLLocation, in context: ModelContext) {
        guard !matches.isEmpty else {
            osmLog("empty lookup for \(card.searchQuery) not cached")
            return
        }
        let automatic = card.locations.filter { !$0.isUserDefined }
        for location in automatic {
            context.delete(location)
        }
        for place in matches.prefix(maxStoresPerCard) {
            let stored = place.makeLocation(isUserDefined: false)
            stored.card = card
            context.insert(stored)
        }
        card.storesSearchedAt = .now
        card.storesSearchLatitude = location.coordinate.latitude
        card.storesSearchLongitude = location.coordinate.longitude
    }
}
