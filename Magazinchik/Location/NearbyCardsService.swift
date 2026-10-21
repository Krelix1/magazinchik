import CoreLocation
import Foundation

/// One saved store point. User pins and OpenStreetMap points are the same kind of row here.
struct ProximityStore: Sendable, Equatable {
    var id: String
    var cardID: UUID
    var latitude: Double
    var longitude: Double
}

/// Local distance check. It does not fetch locations, talk to OpenStreetMap, or touch the screen.
final class NearbyCardsService: @unchecked Sendable {
    /// Inside this distance a card that is not yet shown becomes the nearby one.
    static let enterRadius: CLLocationDistance = 100
    /// A card that is already shown stays until the person is farther than this.
    static let exitRadius: CLLocationDistance = 150
    /// Skip another pass until the person has moved about this far from the last pass.
    static let minimumMovement: CLLocationDistance = 40
    /// A fix coarser than the enter radius cannot show or hide a card.
    static let maximumAccuracy: CLLocationDistance = 100

    private let lock = NSLock()
    private var stores: [ProximityStore] = []
    private var active: Set<UUID> = []
    private var lastSearched: CLLocation?

    var activeIDs: Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func setStores(_ stores: [ProximityStore]) {
        lock.lock()
        self.stores = stores
        if let lastSearched {
            active = Self.matched(stores: stores, from: lastSearched, already: active)
        }
        lock.unlock()
    }

    /// Returns the cards to raise. A short move or a sloppy fix returns the set already chosen.
    func update(userLocation: CLLocation, force: Bool = false) -> Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        guard Self.isReliable(userLocation) else { return active }
        if !force, let lastSearched, lastSearched.distance(from: userLocation) < Self.minimumMovement {
            return active
        }
        active = Self.matched(stores: stores, from: userLocation, already: active)
        lastSearched = userLocation
        return active
    }

    static func isReliable(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= maximumAccuracy
    }

    private static func matched(stores: [ProximityStore], from user: CLLocation, already: Set<UUID>) -> Set<UUID> {
        var nearby = Set<UUID>()
        for store in stores {
            let place = CLLocation(latitude: store.latitude, longitude: store.longitude)
            let radius = already.contains(store.cardID) ? exitRadius : enterRadius
            if user.distance(from: place) <= radius {
                nearby.insert(store.cardID)
            }
        }
        return nearby
    }
}
