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
    @State private var email = ""
    @State private var password = ""

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
            }
        }
    }

    private var canSubmitAccount: Bool {
        email.contains("@") && password.count >= 6 && sync.phase != .signingIn
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            switch sync.phase {
            case .unavailable:
                LabeledContent("Синхронизация", value: sync.statusTitle)
            case .signedOut, .signingIn, .failed where sync.accountEmail == nil:
                TextField("Эл. почта", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Пароль", text: $password)
                    .textContentType(.password)
                Button("Войти") {
                    Task { await sync.signIn(email: email, password: password) }
                }
                .foregroundStyle(.primary)
                .disabled(!canSubmitAccount)
                Button("Создать аккаунт") {
                    Task { await sync.createAccount(email: email, password: password) }
                }
                .foregroundStyle(.primary)
                .disabled(!canSubmitAccount)
                if sync.phase == .signingIn {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Вход…")
                            .foregroundStyle(.secondary)
                    }
                }
            default:
                LabeledContent("Аккаунт", value: sync.accountEmail ?? "")
                LabeledContent("Синхронизация", value: sync.statusTitle)
                Button("Выйти", role: .destructive) {
                    sync.signOut()
                }
            }
            if let lastError = sync.lastError {
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
