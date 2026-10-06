#if DEBUG
import SwiftData
import SwiftUI

/// Demo wallet for Xcode previews.
@MainActor
enum SampleData {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: LoyaltyCard.self, StoreLocation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let cards = [
            LoyaltyCard(storeName: "Пятёрочка", number: "4006381333931", barcodeKind: .ean13, colorHex: "FF453A", symbolName: "basket.fill", note: "Выручай-карта", position: 0),
            LoyaltyCard(storeName: "ВкусВилл", number: "4607001771586", barcodeKind: .ean13, colorHex: "30D158", symbolName: "cart.fill", position: 1),
            LoyaltyCard(storeName: "Кофемания", number: "CM-2041-7788", barcodeKind: .qr, colorHex: "FF9F0A", symbolName: "cup.and.saucer.fill", position: 2),
            LoyaltyCard(storeName: "Лента", number: "96385074", barcodeKind: .ean8, colorHex: "0A84FF", symbolName: "bag.fill", position: 3),
            LoyaltyCard(storeName: "Читай-город", number: "2775001122334", barcodeKind: .code128, colorHex: "BF5AF2", symbolName: "book.fill", position: 4),
        ]
        cards.forEach { container.mainContext.insert($0) }
        cards[0].locations.append(StoreLocation(name: "Пятёрочка", address: "Тверская, 12", latitude: 55.7650, longitude: 37.6050, isUserDefined: true))
        return container
    }()
}

#Preview("Магазинчик") {
    RootView()
        .environment(LocationService())
        .modelContainer(SampleData.container)
}
#endif
