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
        DemoWallet.seedIfEmpty(in: container.mainContext)
        return container
    }()
}

#Preview("Магазинчик") {
    RootView()
        .environment(LocationService())
        .environment(CardSyncService())
        .modelContainer(SampleData.container)
}
#endif
