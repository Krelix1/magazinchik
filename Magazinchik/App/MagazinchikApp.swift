import SwiftData
import SwiftUI

/// One store for the app. Tests reuse it: a second `ModelContainer` for these models traps the process.
enum AppModelStore {
    static let container: ModelContainer = {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let configuration = ModelConfiguration(isStoredInMemoryOnly: testing)
        return try! ModelContainer(
            for: LoyaltyCard.self,
            StoreLocation.self,
            CityRecord.self,
            CachedBrandStore.self,
            configurations: configuration
        )
    }()
}

@main
struct MagazinchikApp: App {
    @State private var location = LocationService()
    @State private var sync = CardSyncService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
                .environment(sync)
                .onOpenURL { url in
                    GoogleSignInBridge.handle(url)
                }
        }
        .modelContainer(AppModelStore.container)
    }
}
