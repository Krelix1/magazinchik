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

/// Wide glass action with an icon over a short caption, for rows like "Сканер · Камера · Фото".
struct GlassTileLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

struct AddCardButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Добавить карту")
    }
}
