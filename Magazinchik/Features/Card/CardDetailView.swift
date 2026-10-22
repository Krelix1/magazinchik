import SwiftData
import SwiftUI
import UIKit

/// The card at the checkout: big code on white, full brightness, nothing else competing for attention.
struct CardDetailView: View {
    let card: LoyaltyCard
    let distance: Double?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CardSyncService.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocationService.self) private var location

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var copiedAt: Date?
    @State private var isShowingStoresMap = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                BarcodePlate(kind: card.barcodeKind, number: card.number, codeHeight: 130)
                actions

                if !card.note.isEmpty {
                    Text(card.note)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .surface(20)
                }

                if !card.automaticPlaces.isEmpty {
                    StoresSection(card: card, user: location.point) {
                        isShowingStoresMap = true
                    }
                }

                if !card.userPlaces.isEmpty {
                    MyPlacesSection(card: card, user: location.point)
                }

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Удалить карту", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(.red)
                .controlSize(.large)
                .padding(.top, 12)
            }
            .padding(.horizontal, Theme.padding)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ScreenBrightness.boost() }
        .onDisappear { ScreenBrightness.restore() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ScreenBrightness.boost() } else { ScreenBrightness.restore() }
        }
        .sheet(isPresented: $isEditing) {
            CardEditorView(card: card)
        }
        .sheet(isPresented: $isShowingStoresMap) {
            StoresMapView(stores: storePins, user: location.point)
        }
        .confirmationDialog("Удалить карту «\(card.storeName)»?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive, action: delete)
        }
        .sensoryFeedback(trigger: copiedAt) { _, new in new == nil ? nil : .success }
    }

    private var header: some View {
        VStack(spacing: 10) {
            CardIcon(card: card, size: 64, logo: LogoMemory.shared.image(for: card.id))
            Text(card.storeName)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            if let caption = nearestCaption {
                Text(caption)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if card.hasAutomaticPlaces {
                    Text(OpenStreetMap.attribution)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if let distance {
                Label("\(CardText.distance(distance)) до магазина", systemImage: "location.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    /// Closest store and how far it is. Shown past the 200 m activation distance; it does not open the code.
    private var nearestCaption: String? {
        guard let nearest = card.nearestAutomaticLocation(to: location.point) else { return nil }
        let metres = location.point?.distance(to: nearest.point)
        return NearbyStoreLabel.caption(name: nearest.name, metres: metres)
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: copyNumber) {
                    Label(copiedAt == nil ? "Номер" : "Скопирован", systemImage: copiedAt == nil ? "doc.on.doc" : "checkmark")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    isEditing = true
                } label: {
                    Label("Изменить", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private var storePins: [StoreMapPin] {
        card.automaticPlaces.map {
            StoreMapPin(id: $0.id, name: $0.name, street: $0.address, latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private func copyNumber() {
        UIPasteboard.general.string = card.number
        copiedAt = .now
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedAt = nil
        }
    }

    private func delete() {
        let card = card
        let cardID = card.id
        dismiss()
        // Delete after the pop so the detail view never renders a deleted model.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            sync.delete(cardID)
            context.delete(card)
            try? context.save()
        }
    }
}

private struct StoresSection: View {
    let card: LoyaltyCard
    let user: GeoPoint?
    let onShowMap: () -> Void

    private var sortedLocations: [StoreLocation] {
        let stores = card.automaticPlaces
        guard let user else { return stores.sorted { $0.name < $1.name } }
        return stores.sorted { user.distance(to: $0.point) < user.distance(to: $1.point) }
    }

    var body: some View {
        let locations = sortedLocations
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Магазины", trailing: "\(locations.count)")

            VStack(spacing: 0) {
                ForEach(locations) { place in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(place.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if let user {
                            Text(CardText.distance(user.distance(to: place.point)))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .surface(20)

            Button(action: onShowMap) {
                Label("На карте", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledContrastButtonStyle())
        }
    }
}

private struct MyPlacesSection: View {
    let card: LoyaltyCard
    let user: GeoPoint?

    private var sortedLocations: [StoreLocation] {
        let mine = card.userPlaces
        guard let user else { return mine.sorted { $0.name < $1.name } }
        return mine.sorted { user.distance(to: $0.point) < user.distance(to: $1.point) }
    }

    var body: some View {
        let locations = sortedLocations
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Мои места", trailing: "\(locations.count)")

            VStack(spacing: 0) {
                ForEach(locations) { place in
                    HStack(spacing: 12) {
                        Image(systemName: "mappin")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            if !place.address.isEmpty {
                                Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if let user {
                            Text(CardText.distance(user.distance(to: place.point)))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .surface(20)
        }
    }
}
