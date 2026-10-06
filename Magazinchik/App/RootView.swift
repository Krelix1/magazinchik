import CoreLocation
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case nearby
    case wallet
}

struct RootView: View {
    @Environment(LocationService.self) private var location
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \LoyaltyCard.position) private var cards: [LoyaltyCard]

    @State private var tab: AppTab = .nearby
    @State private var suggestedID: UUID?

    private var snapshot: NearbySnapshot {
        NearbyRanking.snapshot(
            for: cards.map(\.places),
            from: location.point,
            accuracy: location.location?.horizontalAccuracy ?? 0,
            current: suggestedID
        )
    }

    /// Changes when the person moves ~1 km or the set of cards changes — the moments worth a new MapKit lookup.
    private var storeRefreshKey: String {
        let coarse = location.location.map { "\(Int($0.coordinate.latitude * 100)),\(Int($0.coordinate.longitude * 100))" } ?? "-"
        let names = cards.map { "\($0.id)\($0.searchQuery)\($0.findsStoresAutomatically)" }.joined()
        return coarse + names
    }

    var body: some View {
        let snapshot = snapshot
        TabView(selection: $tab) {
            Tab("Рядом", systemImage: "location.fill", value: AppTab.nearby) {
                NearbyView(cards: cards, snapshot: snapshot)
            }
            Tab("Все", systemImage: "square.grid.2x2.fill", value: AppTab.wallet) {
                WalletView(cards: cards, snapshot: snapshot)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.positive)
        .onChange(of: snapshot.suggestedID, initial: true) { _, newValue in
            suggestedID = newValue
        }
        .sensoryFeedback(trigger: snapshot.suggestedID) { old, new in
            new != nil && new != old ? .success : nil
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: location.start()
            case .background: location.stop()
            default: break
            }
        }
        .task(id: storeRefreshKey) {
            guard let current = location.location else { return }
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            await StoreLocator.refresh(cards, near: current, in: context)
        }
    }
}
