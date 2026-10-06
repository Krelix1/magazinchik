import Foundation
import SwiftData

@Model
final class LoyaltyCard {
    var id: UUID = UUID()
    var storeName: String = ""
    var number: String = ""
    var barcodeKindRaw: String = BarcodeKind.code128.rawValue
    var colorHex: String = "30D158"
    var symbolName: String = "cart.fill"
    @Attribute(.externalStorage) var logoImageData: Data?
    var note: String = ""
    /// Manual position in the wallet; 0 is first.
    var position: Int = 0
    /// What to look for on the map; empty means `storeName`.
    var brandQuery: String = ""
    var findsStoresAutomatically: Bool = true
    var createdAt: Date = Date()

    /// Where and when chain stores were last looked up, so we don't hit MapKit on every launch.
    var storesSearchedAt: Date?
    var storesSearchLatitude: Double?
    var storesSearchLongitude: Double?

    @Relationship(deleteRule: .cascade, inverse: \StoreLocation.card)
    var locations: [StoreLocation] = []

    init(
        storeName: String,
        number: String,
        barcodeKind: BarcodeKind,
        colorHex: String = "30D158",
        symbolName: String = "cart.fill",
        note: String = "",
        position: Int = 0
    ) {
        self.storeName = storeName
        self.number = number
        self.barcodeKindRaw = barcodeKind.rawValue
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.note = note
        self.position = position
    }

    var barcodeKind: BarcodeKind {
        get { BarcodeKind(rawValue: barcodeKindRaw) ?? .code128 }
        set { barcodeKindRaw = newValue.rawValue }
    }

    var searchQuery: String {
        let query = brandQuery.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? storeName : query
    }

    var places: CardPlaces {
        CardPlaces(cardID: id, points: locations.map(\.point))
    }

    func invalidateStoreSearch() {
        storesSearchedAt = nil
        storesSearchLatitude = nil
        storesSearchLongitude = nil
    }
}

@Model
final class StoreLocation {
    var id: UUID = UUID()
    var name: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    /// Added by the person (search or "I'm here"), as opposed to found automatically by brand.
    var isUserDefined: Bool = false
    var card: LoyaltyCard?

    init(name: String, address: String = "", latitude: Double, longitude: Double, isUserDefined: Bool) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.isUserDefined = isUserDefined
    }

    var point: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
}
