import Foundation

struct GeoPoint: Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    /// Great-circle distance in metres.
    func distance(to other: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

struct CardPlaces: Sendable {
    var cardID: UUID
    var points: [GeoPoint]
}

struct NearbySnapshot: Equatable, Sendable {
    /// Distance to the closest known store of each card that has one.
    var distances: [UUID: Double] = [:]
    /// Card IDs: those with a known store sorted by distance first, then the rest in manual order.
    var order: [UUID] = []
    /// The card to put in front of the user right now.
    var suggestedID: UUID?

    static let empty = NearbySnapshot()

    func distance(for id: UUID) -> Double? { distances[id] }
}

enum NearbyRanking {
    /// A card is suggested when the user is within this many metres of one of its stores.
    static let suggestionRadius = 200.0
    /// Once suggested, a card stays suggested until the user is this far away, so it doesn't flicker at the edge.
    static let releaseRadius = 320.0
    /// GPS error that is still added to the radius; beyond it (approximate location) we stop trusting the fix.
    static let maxAccuracyAllowance = 150.0

    /// - Parameters:
    ///   - cards: cards in manual order.
    ///   - user: current position, if known.
    ///   - accuracy: horizontal accuracy of `user` in metres.
    ///   - current: the card suggested last time, for hysteresis.
    static func snapshot(
        for cards: [CardPlaces],
        from user: GeoPoint?,
        accuracy: Double = 0,
        current: UUID? = nil
    ) -> NearbySnapshot {
        guard let user else {
            return NearbySnapshot(order: cards.map(\.cardID))
        }

        var distances: [UUID: Double] = [:]
        for card in cards {
            if let nearest = card.points.map({ user.distance(to: $0) }).min() {
                distances[card.cardID] = nearest
            }
        }

        let manualIndex = Dictionary(uniqueKeysWithValues: cards.enumerated().map { ($1.cardID, $0) })
        let located = cards.map(\.cardID)
            .filter { distances[$0] != nil }
            .sorted { lhs, rhs in
                let l = distances[lhs]!, r = distances[rhs]!
                return l == r ? manualIndex[lhs]! < manualIndex[rhs]! : l < r
            }
        let unlocated = cards.map(\.cardID).filter { distances[$0] == nil }

        let allowance = min(max(accuracy, 0), maxAccuracyAllowance)
        var suggested: UUID?
        if accuracy <= maxAccuracyAllowance * 3 {
            if let current, let distance = distances[current], distance <= releaseRadius + allowance {
                suggested = current
            }
            if let closest = located.first, let distance = distances[closest], distance <= suggestionRadius + allowance {
                if suggested == nil || distance < distances[suggested!]! {
                    suggested = closest
                }
            }
        }

        return NearbySnapshot(distances: distances, order: located + unlocated, suggestedID: suggested)
    }
}
