import MapKit
import SwiftUI

/// One saved store drawn on the card's map. This is the only map in the app.
struct StoreMapPin: Identifiable, Hashable {
    var id: UUID
    var name: String
    var street: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Pins for every store saved on the card. Tapping one shows its name, street, and distance.
struct StoresMapView: View {
    let stores: [StoreMapPin]
    let user: GeoPoint?

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var selected: UUID?

    init(stores: [StoreMapPin], user: GeoPoint?) {
        self.stores = stores
        self.user = user
        _position = State(initialValue: .region(Self.region(for: stores)))
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selected) {
                ForEach(stores) { store in
                    Marker(store.name, coordinate: store.coordinate)
                        .tag(store.id)
                }
            }
            .mapStyle(.standard)
            .safeAreaInset(edge: .bottom) {
                if let store = stores.first(where: { $0.id == selected }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.name)
                            .font(.headline)
                        Text(store.street)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let metres = metres(to: store) {
                            Text(CardText.distance(metres))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Theme.surface)
                }
            }
            .navigationTitle("Магазины")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
            }
        }
    }

    private func metres(to store: StoreMapPin) -> Double? {
        guard let user else { return nil }
        return user.distance(to: GeoPoint(latitude: store.latitude, longitude: store.longitude))
    }

    private static func region(for stores: [StoreMapPin]) -> MKCoordinateRegion {
        let latitudes = stores.map(\.latitude)
        let longitudes = stores.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 52.09, longitude: 23.68),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
            )
        )
    }
}
