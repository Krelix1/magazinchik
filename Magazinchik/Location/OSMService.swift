import CoreLocation
import Foundation

/// Downloads store coordinates once, when a card is added and that brand is not saved for the active city.
/// The request and the reply parsing run off the main actor. Proximity checks never call this.
enum OSMService {
    static func fetchStores(brand: String, city: UserCity) async throws -> [PlaceDraft] {
        try await OpenStreetMap.stores(named: brand, in: city.box, around: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude))
    }
}

/// Whether a brand in a city still needs a download. A saved brand is reused, including after the next launch with no network.
enum BrandCityLookup {
    static func shouldFetch(cachedBrandKeys: Set<String>, brand: String) -> Bool {
        let key = CardText.normalizedName(brand)
        guard key.count >= 2 else { return false }
        return !cachedBrandKeys.contains(key)
    }
}
