import SwiftData
import SwiftUI

@main
struct MagazinchikApp: App {
    @State private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
        }
        .modelContainer(for: [LoyaltyCard.self, StoreLocation.self])
    }
}
