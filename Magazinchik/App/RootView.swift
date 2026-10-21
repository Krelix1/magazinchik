import CoreLocation
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case nearby
    case wallet
}

struct RootView: View {
    @Environment(LocationService.self) private var location
    @Environment(CardSyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \LoyaltyCard.position) private var cards: [LoyaltyCard]
    @Query private var cities: [CityRecord]

    @State private var tab: AppTab = .nearby
    @State private var nearbyIDs: Set<UUID> = []
    @State private var nearbyCards = NearbyCardsService()
    @State private var placeRefresh = PlaceRefresh()
    /// Last local distance pass. Switching tabs reads this; it does not run another one.
    @State private var ranked = NearbySnapshot.empty
    @State private var placeNames: [UUID: String] = [:]
    @State private var nearestNames: [UUID: String] = [:]
    @State private var logos: [UUID: UIImage] = [:]
    @State private var showsMapCredit = false
    @State private var storedPlaces: [StoredPlace] = []
    @State private var cardNames: [UUID: String] = [:]
    @State private var loadedIdentity = ""
    /// True from the tap on a city until that area is saved. The wallet, and its proximity pass, wait until then.
    @State private var deferWallet = false
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    private var activeCity: CityRecord? { cities.first { $0.isActive } }

    private var userPoint: GeoPoint? { location.point }

    /// Card fields only. Touching locations or logo bytes here would run again on every tab switch.
    private var cardIdentity: String {
        cards.map { card in
            "\(card.id)|\(card.position)|\(card.storeName)|\(card.note)|\(card.symbolName)|\(card.colorHex)|\(card.contentRevision)|\(card.storesSearchedAt?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: "\n")
    }

    var body: some View {
        Group {
            if activeCity == nil || deferWallet {
                CityPickerView(requiresChoice: activeCity == nil || deferWallet, defersWallet: $deferWallet)
            } else {
                wallet
            }
        }
        .environment(placeRefresh)
        .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.preferred)
        .task {
            DemoWallet.seedIfEmpty(in: context)
        }
        .task {
            sync.bind(context)
        }
        .onChange(of: activeCity?.id) { _, _ in
            sync.fillStoresForUncachedCards()
        }
    }

    @ViewBuilder
    private var wallet: some View {
        TabView(selection: $tab) {
            Tab("Рядом", systemImage: "location.fill", value: AppTab.nearby) {
                NearbyView(
                    cards: cards,
                    snapshot: ranked,
                    user: userPoint,
                    placeNames: placeNames,
                    nearestNames: nearestNames,
                    logos: logos,
                    showsMapCredit: showsMapCredit
                )
            }
            Tab("Все", systemImage: "square.grid.2x2.fill", value: AppTab.wallet) {
                WalletView(cards: cards, snapshot: ranked, placeNames: placeNames, logos: logos)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(trigger: ranked.suggestedID) { old, new in
            new != nil && new != old ? .success : nil
        }
        .onChange(of: location.locationGeneration) { _, _ in
            rank(force: false)
        }
        .onChange(of: placeRefresh.revision) { _, _ in
            rank(force: true)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                location.start()
                rank(force: false)
            case .background:
                location.stop()
            default:
                break
            }
        }
        .task(id: cardIdentity) {
            let identity = cardIdentity
            guard identity != loadedIdentity else { return }
            loadedIdentity = identity
            await reloadCards()
        }
    }

    /// Copies saved points once, when the cards change. A tab change does not call this.
    private func reloadCards() async {
        let order = cards.map(\.id)
        var names: [UUID: String] = [:]
        var places: [StoredPlace] = []
        var payloads: [LogoPayload] = []
        for card in cards {
            names[card.id] = card.storeName
            for location in card.locations {
                places.append(StoredPlace(
                    id: location.id.uuidString,
                    cardID: card.id,
                    name: location.name,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    isUserDefined: location.isUserDefined
                ))
            }
            if let data = card.logoImageData, !data.isEmpty {
                payloads.append(LogoPayload(id: card.id, data: data))
            }
        }
        cardNames = names
        storedPlaces = places
        nearbyCards.setStores(places.map {
            ProximityStore(id: $0.id, cardID: $0.cardID, latitude: $0.latitude, longitude: $0.longitude)
        })
        nearbyIDs = nearbyCards.activeIDs
        publishLabels(order: order)

        guard !payloads.isEmpty else {
            logos = [:]
            return
        }
        let payloadsToDecode = payloads
        await Task.detached(priority: .userInitiated) {
            LogoMemory.shared.replace(with: payloadsToDecode)
        }.value
        guard !Task.isCancelled else { return }
        logos = LogoMemory.shared.snapshot()
    }

    /// Distances and store titles from the points already copied. No OpenStreetMap and no SwiftData read.
    private func publishLabels(order: [UUID]) {
        let user = userPoint
        let accuracy = location.location?.horizontalAccuracy ?? 0
        let grouped = Dictionary(grouping: storedPlaces, by: \.cardID)
        let inputs = order.map { id in
            CardPlaces(
                cardID: id,
                points: (grouped[id] ?? []).map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }
            )
        }
        var snapshot = NearbyRanking.snapshot(for: inputs, from: user, accuracy: accuracy, current: nil)
        snapshot.suggestedID = closestActiveID(in: snapshot)
        ranked = snapshot

        var titles: [UUID: String] = [:]
        var nearest: [UUID: String] = [:]
        for id in order {
            let rows = grouped[id] ?? []
            if let user, let place = nearestPlace(in: rows, to: user) {
                let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { nearest[id] = name }
            }
            let automatic = rows.filter { !$0.isUserDefined }
            if let user, let place = nearestPlace(in: automatic, to: user) {
                let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let cardName = cardNames[id] ?? ""
                if !name.isEmpty, CardText.normalizedName(name) != CardText.normalizedName(cardName) {
                    titles[id] = name
                }
            }
        }
        placeNames = titles
        nearestNames = nearest
        showsMapCredit = storedPlaces.contains { !$0.isUserDefined }
    }

    private func nearestPlace(in rows: [StoredPlace], to user: GeoPoint) -> StoredPlace? {
        rows.min { lhs, rhs in
            user.distance(to: GeoPoint(latitude: lhs.latitude, longitude: lhs.longitude))
                < user.distance(to: GeoPoint(latitude: rhs.latitude, longitude: rhs.longitude))
        }
    }

    /// The closest card that is inside the enter radius, or still inside the exit radius.
    private func closestActiveID(in ranked: NearbySnapshot) -> UUID? {
        nearbyIDs.min { lhs, rhs in
            (ranked.distance(for: lhs) ?? .greatestFiniteMagnitude) < (ranked.distance(for: rhs) ?? .greatestFiniteMagnitude)
        }
    }

    /// Local distance only, using the points copied when the cards last changed. Nothing here calls OpenStreetMap.
    private func rank(force: Bool) {
        guard let fix = location.location else { return }
        let next = nearbyCards.update(userLocation: fix, force: force)
        if next != nearbyIDs {
            nearbyIDs = next
        }
        publishLabels(order: cards.map(\.id))
    }
}

/// One saved store, copied out of SwiftData so a later tab switch does not read the store list again.
private struct StoredPlace: Sendable {
    var id: String
    var cardID: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var isUserDefined: Bool
}
