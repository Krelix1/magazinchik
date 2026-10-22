import SwiftUI

/// One card as a soft list row: logo, name, a quiet second line, distance on the right.
struct CardRow: View {
    let card: LoyaltyCard
    var distance: Double?
    var placeName: String?
    var logo: UIImage?
    var isSuggested = false

    var body: some View {
        HStack(spacing: 14) {
            CardIcon(card: card, size: 44, logo: logo)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.storeName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let placeName, !placeName.isEmpty {
                    Text(placeName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !card.note.isEmpty {
                    Text(card.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let distance {
                Text(CardText.distance(distance))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .surface(20)
        .contentShape(.rect(cornerRadius: 20))
    }
}

struct EmptyWalletView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wallet.bifold")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            Text("Здесь будут ваши карты")
                .font(.title3.weight(.semibold))
            Text("Добавьте скидочную карту вручную или по фото — штрихкод и номер распознаются сами.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onAdd) {
                Label("Добавить карту", systemImage: "plus")
            }
            .buttonStyle(FilledContrastButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, 12)
    }
}
