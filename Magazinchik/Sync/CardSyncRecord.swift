import Foundation
import SwiftData

/// One custom place on a card. OpenStreetMap stores are not part of this value.
struct CardSyncPlace: Codable, Equatable, Sendable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
}

/// The Firestore document for `users/{uid}/cards/{cardId}`.
/// Photos and automatic map stores never enter this value.
struct CardSyncRecord: Equatable, Sendable {
    var id: UUID
    var storeName: String
    var barcodeKind: String
    var barcodePayload: String
    var sortOrder: Int
    var note: String
    var colorHex: String
    var symbolName: String
    var updatedAt: Date
    var places: [CardSyncPlace]

    static let fieldNames: Set<String> = [
        "storeName", "barcodeKind", "barcodePayload", "sortOrder",
        "note", "colorHex", "symbolName", "updatedAt", "places",
    ]

    static let placeFieldNames: Set<String> = ["name", "address", "latitude", "longitude"]

    /// Body written to Firestore. `id` stays in the document path.
    var document: CardSyncDocument {
        CardSyncDocument(
            storeName: storeName,
            barcodeKind: barcodeKind,
            barcodePayload: barcodePayload,
            sortOrder: sortOrder,
            note: note,
            colorHex: colorHex,
            symbolName: symbolName,
            updatedAt: updatedAt,
            places: places
        )
    }

    @MainActor
    init(_ card: LoyaltyCard) {
        id = card.id
        storeName = card.storeName
        barcodeKind = card.barcodeKindRaw
        barcodePayload = card.number
        sortOrder = card.position
        note = card.note
        colorHex = card.colorHex
        symbolName = card.symbolName
        updatedAt = card.updatedAt
        places = card.userPlaces.map {
            CardSyncPlace(name: $0.name, address: $0.address, latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    init(
        id: UUID,
        storeName: String,
        barcodeKind: String,
        barcodePayload: String,
        sortOrder: Int,
        note: String,
        colorHex: String,
        symbolName: String,
        updatedAt: Date,
        places: [CardSyncPlace]
    ) {
        self.id = id
        self.storeName = storeName
        self.barcodeKind = barcodeKind
        self.barcodePayload = barcodePayload
        self.sortOrder = sortOrder
        self.note = note
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.updatedAt = updatedAt
        self.places = places
    }

    @MainActor
    func makeCard(in context: ModelContext) -> LoyaltyCard {
        let card = LoyaltyCard(
            storeName: storeName,
            number: barcodePayload,
            barcodeKind: BarcodeKind(rawValue: barcodeKind) ?? .code128,
            colorHex: colorHex,
            symbolName: symbolName,
            note: note,
            position: sortOrder
        )
        card.id = id
        card.createdAt = updatedAt
        card.updatedAt = updatedAt
        context.insert(card)
        apply(to: card, in: context)
        return card
    }

    /// Copies synced fields onto a card. The logo and OpenStreetMap stores stay, unless the store name changed and those stores belong to the old name.
    @MainActor
    func apply(to card: LoyaltyCard, in context: ModelContext) {
        guard !matches(card) else { return }
        let nameChanged = card.storeName != storeName
        card.storeName = storeName
        card.number = barcodePayload
        card.barcodeKindRaw = barcodeKind
        card.position = sortOrder
        card.note = note
        card.colorHex = colorHex
        card.symbolName = symbolName
        card.updatedAt = updatedAt
        if nameChanged {
            card.invalidateStoreSearch()
            for location in card.locations.filter({ !$0.isUserDefined }) {
                context.delete(location)
            }
        }
        if !Self.samePlaces(card.userPlaces, places) {
            for location in card.locations.filter(\.isUserDefined) {
                context.delete(location)
            }
            for place in places {
                let location = StoreLocation(
                    name: place.name,
                    address: place.address,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    isUserDefined: true
                )
                location.card = card
                context.insert(location)
            }
        }
        card.contentRevision += 1
    }

    @MainActor
    func matches(_ card: LoyaltyCard) -> Bool {
        card.storeName == storeName
            && card.number == barcodePayload
            && card.barcodeKindRaw == barcodeKind
            && card.position == sortOrder
            && card.note == note
            && card.colorHex == colorHex
            && card.symbolName == symbolName
            && abs(card.updatedAt.timeIntervalSince(updatedAt)) <= CardSyncMerge.tie
            && Self.samePlaces(card.userPlaces, places)
    }

    @MainActor
    private static func samePlaces(_ locations: [StoreLocation], _ places: [CardSyncPlace]) -> Bool {
        let local = locations.map {
            CardSyncPlace(name: $0.name, address: $0.address, latitude: $0.latitude, longitude: $0.longitude)
        }
        return local == places
    }
}

/// Codable view of the document. Kept separate so `id` cannot be encoded by accident.
struct CardSyncDocument: Codable, Equatable, Sendable {
    var storeName: String
    var barcodeKind: String
    var barcodePayload: String
    var sortOrder: Int
    var note: String
    var colorHex: String
    var symbolName: String
    var updatedAt: Date
    var places: [CardSyncPlace]
}

enum CardSyncWinner: Equatable, Sendable {
    case local
    case remote
}

enum CardSyncMerge {
    /// Timestamps closer than this are the same write coming back from the server.
    static let tie: TimeInterval = 0.001

    static func winner(local: Date, remote: Date) -> CardSyncWinner {
        remote.timeIntervalSince(local) > tie ? .remote : .local
    }
}
