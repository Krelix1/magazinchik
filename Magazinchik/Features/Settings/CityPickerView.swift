import SwiftData
import SwiftUI

/// Asks for a city as a centre and a bounding box. Shown on first launch, and again from settings.
struct CityPickerView: View {
    var requiresChoice: Bool = false
    /// Keeps the wallet unmounted until the chosen area is saved, so that save does not start a proximity pass.
    var defersWallet: Binding<Bool> = .constant(false)

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var query = ""
    @State private var matches: [CityMatch] = []
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Название города", text: $query)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    Button {
                        Task { await search() }
                    } label: {
                        if isSearching {
                            ProgressView()
                        } else {
                            Text("Найти")
                        }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearching || isSaving)
                } footer: {
                    Text("Сохраняется область города, не только его название. Магазины новых карт ищутся в ней один раз.")
                }

                if let failure {
                    Section {
                        Text(failure)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(matches) { match in
                        Button {
                            choose(match)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.name)
                                    .foregroundStyle(.primary)
                                if !match.detail.isEmpty {
                                    Text(match.detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSaving {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Сохраняем город…")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(requiresChoice ? "Выберите город" : "Город")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !requiresChoice {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Закрыть")
                    }
                }
            }
        }
    }

    private func choose(_ match: CityMatch) {
        guard !isSaving else { return }
        isSaving = true
        defersWallet.wrappedValue = true
        let match = match
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else {
                isSaving = false
                defersWallet.wrappedValue = false
                return
            }
            CityStore.activate(match, in: context)
            isSaving = false
            defersWallet.wrappedValue = false
            if !requiresChoice { dismiss() }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, !isSaving else { return }
        isSearching = true
        failure = nil
        defer { isSearching = false }
        do {
            let found = try await OpenStreetMap.searchCities(text)
            matches = found
            if found.isEmpty { failure = "Такой город не нашёлся." }
        } catch {
            matches = []
            failure = "Не удалось найти город. Проверьте сеть и попробуйте ещё раз."
        }
    }
}
