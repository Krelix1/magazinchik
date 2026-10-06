import MapKit
import SwiftUI

/// Find a specific store on Apple Maps and attach it to the card.
struct PlaceSearchView: View {
    let onPick: (PlaceDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var query: String
    @State private var results: [PlaceDraft] = []
    @State private var isSearching = false

    init(initialQuery: String, onPick: @escaping (PlaceDraft) -> Void) {
        self.onPick = onPick
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            List(results) { place in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                            .font(.body.weight(.medium))
                        if !place.address.isEmpty {
                            Text(place.address)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    if let user = location.point {
                        Text(CardText.distance(user.distance(to: GeoPoint(latitude: place.latitude, longitude: place.longitude))))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        onPick(place)
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Добавить \(place.name)")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .overlay {
                if results.isEmpty {
                    if isSearching {
                        ProgressView()
                    } else {
                        ContentUnavailableView(
                            query.isEmpty ? "Найдите магазин" : "Ничего не нашлось",
                            systemImage: "mappin.and.ellipse",
                            description: Text("Введите название сети или адрес.")
                        )
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Магазин или адрес")
            .task(id: query) { await search() }
            .navigationTitle("Адрес магазина")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            return
        }
        do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
        isSearching = true
        defer { isSearching = false }
        let items = (try? await StoreLocator.search(text, near: location.location?.coordinate, radius: 20_000)) ?? []
        guard !Task.isCancelled else { return }
        results = items.map { PlaceDraft($0) }
    }
}
