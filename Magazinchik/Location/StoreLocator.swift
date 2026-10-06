import CoreLocation
import MapKit
import SwiftData

/// A store address picked by the person or found on the map, before it's saved to a card.
struct PlaceDraft: Identifiable, Hashable {
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

    init(_ item: MKMapItem) {
        let placemark = item.placemark
        self.init(
            name: item.name ?? placemark.name ?? "",
            address: placemark.title ?? "",
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude
        )
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

@MainActor
enum StoreLocator {
    static let searchRadius: CLLocationDistance = 5_000
    static let refreshDistance: CLLocationDistance = 2_000
    static let maxAge: TimeInterval = 7 * 24 * 3600
    static let maxStoresPerCard = 15

    static func needsRefresh(_ card: LoyaltyCard, near location: CLLocation, now: Date = .now) -> Bool {
        guard card.findsStoresAutomatically, !card.searchQuery.isEmpty else { return false }
        guard let date = card.storesSearchedAt,
              let latitude = card.storesSearchLatitude,
              let longitude = card.storesSearchLongitude else { return true }
        if now.timeIntervalSince(date) > maxAge { return true }
        return location.distance(from: CLLocation(latitude: latitude, longitude: longitude)) > refreshDistance
    }

    /// Finds chain stores around `location` for each card that needs it.
    /// Sequential on purpose: MapKit throttles bursts of searches from one app.
    static func refresh(_ cards: [LoyaltyCard], near location: CLLocation, in context: ModelContext) async {
        for card in cards where needsRefresh(card, near: location) {
            guard !Task.isCancelled else { return }
            let query = card.searchQuery
            guard let items = try? await search(query, near: location.coordinate, radius: searchRadius, pointsOfInterestOnly: true) else {
                continue
            }
            guard !card.isDeleted, card.searchQuery == query else { continue }

            let found = items
                .filter { CardText.place($0.name ?? "", matchesBrand: query) }
                .prefix(maxStoresPerCard)
                .map { PlaceDraft($0).makeLocation(isUserDefined: false) }

            let stale = card.locations.filter { !$0.isUserDefined }
            card.locations.removeAll { !$0.isUserDefined }
            stale.forEach { context.delete($0) }
            card.locations.append(contentsOf: found)

            card.storesSearchedAt = .now
            card.storesSearchLatitude = location.coordinate.latitude
            card.storesSearchLongitude = location.coordinate.longitude
        }
        try? context.save()
    }

    static func search(
        _ query: String,
        near center: CLLocationCoordinate2D?,
        radius: CLLocationDistance = searchRadius,
        pointsOfInterestOnly: Bool = false
    ) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = pointsOfInterestOnly ? .pointOfInterest : [.pointOfInterest, .address]
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
            if pointsOfInterestOnly { request.regionPriority = .required }
        }
        return try await MKLocalSearch(request: request).start().mapItems
    }
}
