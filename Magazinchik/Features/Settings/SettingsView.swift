import SwiftData
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Система"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    var preferred: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CardSyncService.self) private var sync
    @Query private var cities: [CityRecord]
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @State private var isPickingCity = false
    @State private var isShowingAuth = false

    private var activeCityName: String {
        cities.first { $0.isActive }?.name ?? "Не выбран"
    }

    private var appearance: Binding<AppAppearance> {
        Binding {
            AppAppearance(rawValue: appearanceRaw) ?? .system
        } set: {
            appearanceRaw = $0.rawValue
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection

                Section {
                    Button {
                        isPickingCity = true
                    } label: {
                        LabeledContent("Город", value: activeCityName)
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Новые карты ищут магазины в этом городе. Точки других городов остаются сохранёнными.")
                }

                Section {
                    Picker("Оформление", selection: appearance) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Оформление")
                } footer: {
                    Text("Тёмная включает тёмную палитру приложения.")
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPickingCity) {
                CityPickerView()
            }
            .sheet(isPresented: $isShowingAuth) {
                AccountAuthView()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            switch sync.phase {
            case .unavailable:
                LabeledContent("Синхронизация", value: sync.statusTitle)
            case .signedOut, .signingIn, .failed where sync.accountEmail == nil:
                Button {
                    isShowingAuth = true
                } label: {
                    LabeledContent("Аккаунт", value: "Войти")
                }
                .foregroundStyle(.primary)
            default:
                LabeledContent("Аккаунт", value: sync.accountEmail ?? "")
                LabeledContent("Синхронизация", value: sync.statusTitle)
                Button("Выйти", role: .destructive) {
                    sync.signOut()
                }
            }
            if sync.accountEmail != nil, let lastError = sync.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(Color(hex: "FF453A"))
            }
        } header: {
            Text("Аккаунт")
        } footer: {
            Text(sync.phase == .unavailable
                ? "Добавьте GoogleService-Info.plist в приложение. Пока его нет, карты остаются на этом телефоне."
                : "Между телефонами уходят карты и ваши места. Фото и точки OpenStreetMap остаются на устройстве.")
        }
    }
}
