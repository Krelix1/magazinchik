import SwiftUI

extension View {
    /// `.glassProminent` for the selected / primary state, `.glass` otherwise.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }
}

struct SettingsGearButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(.primary)
        .accessibilityLabel("Настройки")
    }
}

struct AddCardButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(.primary)
        .accessibilityLabel("Добавить карту")
    }
}

extension ToolbarContent {
    /// The button draws its own glass, so the bar must not add a second plate behind it.
    func glassToolbarItem() -> some ToolbarContent {
        sharedBackgroundVisibility(.hidden)
    }
}

/// Same glass circle as the gear and the add button. The spinner replaces the symbol only while a short location read is in flight.
struct RefreshPlaceButton: View {
    @Environment(LocationService.self) private var location
    @Environment(PlaceRefresh.self) private var refresh

    var body: some View {
        Button {
            Task { await refresh.runManual(location: location) }
        } label: {
            if refresh.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "location.fill.viewfinder")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(.primary)
        .allowsHitTesting(!refresh.isRunning)
        .accessibilityLabel("Обновить место")
    }
}

extension View {
    /// «Рядом» and «Все»: refresh on the left, add then settings flush right.
    func storeScreenToolbar(
        isAdding: Binding<Bool>,
        isShowingSettings: Binding<Bool>
    ) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                RefreshPlaceButton()
            }
            .glassToolbarItem()
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    AddCardButton { isAdding.wrappedValue = true }
                    SettingsGearButton { isShowingSettings.wrappedValue = true }
                }
            }
            .glassToolbarItem()
        }
    }
}
