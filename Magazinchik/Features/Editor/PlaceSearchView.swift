import CoreLocation
import SwiftUI

/// Find a specific store by address and attach it to the card. Results come from OpenStreetMap.
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
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
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
            .safeAreaInset(edge: .bottom) {
                Text(OpenStreetMap.attribution)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
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
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        guard !Task.isCancelled else { return }

        let coordinate = location.location?.coordinate
        let origin = coordinate.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }

        let addresses = await Self.addresses(for: text, near: coordinate)
        guard !Task.isCancelled else { return }
        results = PlaceSearch.results(query: text, near: origin, nearby: nil, addresses: addresses)

        guard let coordinate else { return }
        let nearby = await Self.nearbyPlaces(named: text, near: coordinate)
        guard !Task.isCancelled else { return }
        results = PlaceSearch.results(query: text, near: origin, nearby: nearby, addresses: addresses)
    }

    /// Address lookup. Not on the main actor, so typing stays responsive while the server answers.
    private nonisolated static func addresses(for text: String, near coordinate: CLLocationCoordinate2D?) async -> [PlaceDraft] {
        do {
            return try await OpenStreetMap.geocode(text, near: coordinate)
        } catch {
            osmLog("address lookup failed for \(text) (\(error))")
            return []
        }
    }

    /// Nearby name lookup. `nil` means it failed; an empty list means the server found nothing. Neither drops addresses.
    private nonisolated static func nearbyPlaces(named text: String, near coordinate: CLLocationCoordinate2D) async -> [PlaceDraft]? {
        do {
            return try await OpenStreetMap.nearbyPlaces(
                named: text,
                near: coordinate,
                radius: PlaceOrdering.pickerRadius
            )
        } catch {
            osmLog("nearby lookup failed for \(text), address results kept (\(error))")
            return nil
        }
    }
}
