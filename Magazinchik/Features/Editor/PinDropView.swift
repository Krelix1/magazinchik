import MapKit
import SwiftUI

/// One point the person drops. The card can activate here when the store is missing from OpenStreetMap.
/// This is not the store list that used to sit on the card.
struct PinDropView: View {
    let onPick: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var span: MKCoordinateSpan

    init(initial: CLLocationCoordinate2D?, onPick: @escaping (CLLocationCoordinate2D) -> Void) {
        let start = initial ?? CLLocationCoordinate2D(latitude: 55.75124, longitude: 37.61842)
        let span = MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        self.onPick = onPick
        _center = State(initialValue: start)
        _span = State(initialValue: span)
        _position = State(initialValue: .region(MKCoordinateRegion(center: start, span: span)))
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()
                }
                .mapStyle(.standard)
                .onMapCameraChange(frequency: .continuous) { context in
                    center = context.camera.centerCoordinate
                    span = context.region.span
                }
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        center = coordinate
                        position = .region(MKCoordinateRegion(center: coordinate, span: span))
                    }
                )
                .overlay {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.primary)
                        .offset(y: -16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                Text("Сдвиньте карту — точка встанет в центр")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Theme.surface)
            }
            .navigationTitle("Точка на карте")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Закрыть")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onPick(center)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .tint(.primary)
                    .accessibilityLabel("Сохранить точку")
                }
                .glassToolbarItem()
            }
        }
    }
}
