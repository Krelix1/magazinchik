import Foundation
import SwiftData

/// Fills a card from the brand's saved stores in the active city, or downloads them once.
/// SwiftData writes stay here. The OpenStreetMap download does not: it runs off the main actor.
@MainActor
enum BrandStoreCache {
    static func ensureStores(for cardID: UUID, in context: ModelContext) async {
        guard let card = card(cardID, in: context), card.findsStoresAutomatically else { return }
        let brand = card.searchQuery
        let brandKey = CardText.normalizedName(brand)
        guard brandKey.count >= 2 else { return }
        guard let city = activeCity(in: context) else { return }
        let cached = cachedStores(brandKey: brandKey, cityID: city.id, in: context)
        let cacheIsComplete = !cached.isEmpty && cached.allSatisfy(\.isFullCityList)
        if cacheIsComplete, card.cachedCityID == city.id, card.cachedBrandKey == brandKey, card.hasAutomaticPlaces {
            return
        }

        if !cached.isEmpty, cached.allSatisfy(\.isFullCityList) {
            write(cached.map { ($0.name, $0.address, $0.latitude, $0.longitude) }, brandKey: brandKey, cityID: city.id, to: card, in: context)
            return
        }
        for row in cached {
            context.delete(row)
        }

        guard BrandCityLookup.shouldFetch(cachedBrandKeys: [], brand: brand) else { return }
        let drafts: [PlaceDraft]
        do {
            drafts = try await OSMService.fetchStores(brand: brand, city: city)
        } catch is CancellationError {
            return
        } catch {
            osmLog("city lookup failed for \(brand), nothing cached (\(error))")
            return
        }
        guard !Task.isCancelled else { return }
        guard !drafts.isEmpty else {
            osmLog("empty city lookup for \(brand) not cached")
            return
        }
        let fetchedAt = Date()
        for place in drafts {
            context.insert(CachedBrandStore(
                brandKey: brandKey,
                cityID: city.id,
                name: place.name,
                address: place.address,
                latitude: place.latitude,
                longitude: place.longitude,
                fetchedAt: fetchedAt
            ))
        }
        write(drafts.map { ($0.name, $0.address, $0.latitude, $0.longitude) }, brandKey: brandKey, cityID: city.id, to: card, in: context)
    }

    private static func write(_ places: [(name: String, address: String, latitude: Double, longitude: Double)], brandKey: String, cityID: UUID, to card: LoyaltyCard, in context: ModelContext) {
        for location in card.locations.filter({ !$0.isUserDefined }) {
            context.delete(location)
        }
        for place in places {
            let stored = StoreLocation(name: place.name, address: place.address, latitude: place.latitude, longitude: place.longitude, isUserDefined: false)
            stored.card = card
            context.insert(stored)
        }
        card.cachedBrandKey = brandKey
        card.cachedCityID = cityID
        card.storesSearchedAt = .now
        card.contentRevision += 1
        try? context.save()
    }

    private static func card(_ id: UUID, in context: ModelContext) -> LoyaltyCard? {
        let cards = (try? context.fetch(FetchDescriptor<LoyaltyCard>())) ?? []
        return cards.first { $0.id == id }
    }

    private static func activeCity(in context: ModelContext) -> UserCity? {
        let cities = (try? context.fetch(FetchDescriptor<CityRecord>())) ?? []
        return cities.first { $0.isActive }?.city
    }

    private static func cachedStores(brandKey: String, cityID: UUID, in context: ModelContext) -> [CachedBrandStore] {
        let rows = (try? context.fetch(FetchDescriptor<CachedBrandStore>())) ?? []
        return rows.filter { $0.brandKey == brandKey && $0.cityID == cityID }
    }
}
