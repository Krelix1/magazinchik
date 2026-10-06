import SwiftUI

/// Opens first. Near a store, its card is the hero with the code already on it; everything else follows by distance.
struct NearbyView: View {
    let cards: [LoyaltyCard]
    let snapshot: NearbySnapshot

    @Environment(LocationService.self) private var location
    @State private var isAdding = false

    private var cardsByID: [UUID: LoyaltyCard] {
        Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
    }

    var body: some View {
        let byID = cardsByID
        let suggested = snapshot.suggestedID.flatMap { byID[$0] }
        let others = snapshot.order.compactMap { byID[$0] }.filter { $0.id != suggested?.id }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LocationAccessBanner()

                    if cards.isEmpty {
                        EmptyWalletView { isAdding = true }
                    } else {
                        if let suggested {
                            NavigationLink(value: suggested) {
                                SuggestedCardHero(
                                    card: suggested,
                                    distance: snapshot.distance(for: suggested.id),
                                    storeName: nearestStoreName(of: suggested)
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                        } else if location.isAuthorized, location.location != nil {
                            NoStoreNearbyNote()
                        }

                        if !others.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel(title: suggested == nil ? "Ваши карты" : "Ещё")
                                ForEach(others) { card in
                                    NavigationLink(value: card) {
                                        CardRow(card: card, distance: snapshot.distance(for: card.id))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.padding)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .animation(Theme.spring, value: snapshot.suggestedID)
                .animation(Theme.spring, value: snapshot.order)
            }
            .screenBackground()
            .navigationTitle("Рядом")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddCardButton { isAdding = true }
                }
            }
            .navigationDestination(for: LoyaltyCard.self) { card in
                CardDetailView(card: card, distance: snapshot.distance(for: card.id))
            }
            .sheet(isPresented: $isAdding) {
                CardEditorView(card: nil)
            }
        }
    }

    private func nearestStoreName(of card: LoyaltyCard) -> String? {
        guard let user = location.point else { return nil }
        let nearest = card.locations.min { user.distance(to: $0.point) < user.distance(to: $1.point) }
        guard let nearest else { return nil }
        return nearest.address.isEmpty ? nearest.name : nearest.address
    }
}

private struct SuggestedCardHero: View {
    let card: LoyaltyCard
    let distance: Double?
    let storeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                CardIcon(card: card, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.storeName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Label {
                        Text(distance.map { "Вы рядом · \(CardText.distance($0))" } ?? "Вы рядом")
                    } icon: {
                        Image(systemName: "location.fill")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.positive)
                }
                Spacer(minLength: 0)
            }

            BarcodePlate(kind: card.barcodeKind, number: card.number, codeHeight: 96)

            if let storeName, !storeName.isEmpty {
                Text(storeName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(18)
        .surface(28)
        .contentShape(.rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открыть карту крупно")
    }
}

private struct NoStoreNearbyNote: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location")
                .foregroundStyle(.secondary)
            Text("Рядом нет магазинов ваших карт. Когда окажетесь у кассы, нужная карта встанет сюда.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

/// Explains each location permission state and offers the one action that helps. Hidden when location is precise.
struct LocationAccessBanner: View {
    @Environment(LocationService.self) private var location

    var body: some View {
        switch location.access {
        case .precise:
            EmptyView()
        case .notDetermined:
            banner(
                icon: "location.circle",
                title: "Нужная карта — сразу",
                text: "Разрешите геолокацию, и у магазина его карта окажется первой. Координаты не покидают телефон.",
                action: "Разрешить"
            ) { location.requestPermission() }
        case .denied:
            banner(
                icon: "location.slash",
                title: "Геолокация выключена",
                text: "Карты показаны в вашем порядке. Включите доступ в Настройках, чтобы видеть ближайший магазин.",
                action: "Открыть Настройки"
            ) { location.openSettings() }
        case .restricted:
            banner(
                icon: "location.slash",
                title: "Геолокация ограничена",
                text: "Доступ запрещён настройками устройства. Карты показаны в вашем порядке.",
                action: nil
            ) {}
        case .approximate:
            banner(
                icon: "scope",
                title: "Примерная геопозиция",
                text: "С ней не понять, у какого вы магазина. Разрешите точную — только пока открыто приложение.",
                action: "Уточнить"
            ) { location.requestPreciseLocation() }
        }
    }

    private func banner(icon: String, title: String, text: String, action: String?, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.positive)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action, action: perform)
                        .buttonStyle(.glassProminent)
                        .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .surface(22)
    }
}
