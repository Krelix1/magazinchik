import Foundation
import SwiftData

/// The four cards from the redesign mockups, inserted only when the wallet is empty.
@MainActor
enum DemoWallet {
    /// Standing here puts Пятёрочка about 50 m away, inside the 100 m enter radius.
    static let demoLatitude = 55.7650
    static let demoLongitude = 37.6050

    static func seedIfEmpty(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<LoyaltyCard>())) ?? 0
        guard count == 0 else { return }

        let cards = makeCards()
        cards.forEach { context.insert($0) }
        try? context.save()
        remember(cards)
    }

    /// Sample cards inserted for an empty wallet. Sync does not upload them until the person edits one.
    static func isUntouchedSample(_ card: LoyaltyCard) -> Bool {
        seededIDs.contains(card.id) && card.updatedAt <= card.createdAt
    }

    private static let seededIDsKey = "demo.seededCardIDs"

    private static var seededIDs: Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: seededIDsKey) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private static func remember(_ cards: [LoyaltyCard]) {
        let ids = seededIDs.union(cards.map(\.id))
        UserDefaults.standard.set(ids.map(\.uuidString).sorted(), forKey: seededIDsKey)
    }

    static func makeCards() -> [LoyaltyCard] {
        let pyaterochka = LoyaltyCard(
            storeName: "Пятёрочка",
            number: "4006381333931",
            barcodeKind: .ean13,
            colorHex: "FF453A",
            symbolName: "basket.fill",
            note: "Выручай-карта",
            position: 0
        )
        pyaterochka.findsStoresAutomatically = false
        pyaterochka.locations.append(
            StoreLocation(
                name: "Пятёрочка",
                address: "Тверская, 12",
                latitude: demoLatitude + 0.00045,
                longitude: demoLongitude,
                isUserDefined: true
            )
        )

        let vkusvill = LoyaltyCard(
            storeName: "ВкусВилл",
            number: "4607001771586",
            barcodeKind: .ean13,
            colorHex: "30D158",
            symbolName: "cart.fill",
            position: 1
        )
        vkusvill.findsStoresAutomatically = false
        vkusvill.locations.append(
            StoreLocation(
                name: "ВкусВилл",
                address: "Большая Никитская, 21",
                latitude: demoLatitude + 0.00404,
                longitude: demoLongitude,
                isUserDefined: true
            )
        )

        let magnit = LoyaltyCard(
            storeName: "Магнит",
            number: "4600721000011",
            barcodeKind: .ean13,
            colorHex: "FF375F",
            symbolName: "bag.fill",
            position: 2
        )
        magnit.findsStoresAutomatically = false
        magnit.locations.append(
            StoreLocation(
                name: "Магнит",
                address: "Пятницкая, 8",
                latitude: demoLatitude + 0.0108,
                longitude: demoLongitude,
                isUserDefined: true
            )
        )

        let perekrestok = LoyaltyCard(
            storeName: "Перекрёсток",
            number: "4601234000017",
            barcodeKind: .ean13,
            colorHex: "FF9F0A",
            symbolName: "cart.fill",
            position: 3
        )
        perekrestok.findsStoresAutomatically = false
        perekrestok.locations.append(
            StoreLocation(
                name: "Перекрёсток",
                address: "Арбат, 36",
                latitude: demoLatitude + 0.0216,
                longitude: demoLongitude,
                isUserDefined: true
            )
        )

        return [pyaterochka, vkusvill, magnit, perekrestok]
    }
}
