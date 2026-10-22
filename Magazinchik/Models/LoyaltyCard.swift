import Foundation
import SwiftData

@Model
final class LoyaltyCard {
    var id: UUID = UUID()
    var storeName: String = ""
    var number: String = ""
    var barcodeKindRaw: String = BarcodeKind.code128.rawValue
    var colorHex: String = "8E8E93"
    var symbolName: String = "cart.fill"
    @Attribute(.externalStorage) var logoImageData: Data?
    var note: String = ""
    /// Manual position in the wallet; 0 is first.
    var position: Int = 0
    /// Kept so older cards still open. Lookups use `storeName`, not this field.
    var brandQuery: String = ""
    var findsStoresAutomatically: Bool = true
    var createdAt: Date = Date()
    /// Last edit on this phone or from another one. The later timestamp wins.
    var updatedAt: Date = Date()

    /// Where and when this card last received store coordinates. The download itself is once per brand and city.
    var storesSearchedAt: Date?
    var storesSearchLatitude: Double?
    var storesSearchLongitude: Double?
    /// Brand and city those automatic points belong to. A second card of the same brand copies them instead of calling OpenStreetMap.
    var cachedBrandKey: String = ""
    var cachedCityID: UUID?
    /// Bumped when the card's saved points or logo change, so lists can refresh without reading every store on each redraw.
    var contentRevision: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \StoreLocation.card)
    var locations: [StoreLocation] = []

    init(
        storeName: String,
        number: String,
        barcodeKind: BarcodeKind,
        colorHex: String = "8E8E93",
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
        self.updatedAt = createdAt
    }

    var barcodeKind: BarcodeKind {
        get { BarcodeKind(rawValue: barcodeKindRaw) ?? .code128 }
        set { barcodeKindRaw = newValue.rawValue }
    }

    /// The name sent to OpenStreetMap. A card called «Санта» looks for «Санта».
    var searchQuery: String {
        storeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAutomaticPlaces: Bool {
        locations.contains { !$0.isUserDefined }
    }

    var places: CardPlaces {
        CardPlaces(cardID: id, points: locations.map(\.point))
    }

    /// Closest saved store, including one found on the map without an address the person typed.
    func nearestLocation(to user: GeoPoint?) -> StoreLocation? {
        nearest(among: locations, to: user)
    }

    /// Closest store OpenStreetMap found. Manual pins stay out of this line.
    func nearestAutomaticLocation(to user: GeoPoint?) -> StoreLocation? {
        nearest(among: locations.filter { !$0.isUserDefined }, to: user)
    }

    var userPlaces: [StoreLocation] {
        locations.filter(\.isUserDefined)
    }

    /// Stores found for this brand in the city. The person's own pins are not in this list.
    var automaticPlaces: [StoreLocation] {
        locations.filter { !$0.isUserDefined }
    }

    private func nearest(among places: [StoreLocation], to user: GeoPoint?) -> StoreLocation? {
        guard let user, !places.isEmpty else { return nil }
        return places.min { user.distance(to: $0.point) < user.distance(to: $1.point) }
    }

    /// Automatic store name for a card row, when it says more than the card title. «Санта - 54» under a card named «Санта».
    func nearbyStoreTitle(to user: GeoPoint?) -> String? {
        guard let place = nearestAutomaticLocation(to: user) else { return nil }
        let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard CardText.normalizedName(name) != CardText.normalizedName(storeName) else { return nil }
        return name
    }

    func invalidateStoreSearch() {
        storesSearchedAt = nil
        storesSearchLatitude = nil
        storesSearchLongitude = nil
        cachedBrandKey = ""
        cachedCityID = nil
    }
}

@Model
final class StoreLocation {
    var id: UUID = UUID()
    var name: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    /// Added by the person («Я сейчас здесь» or a typed address). Automatic OpenStreetMap matches are false.
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
