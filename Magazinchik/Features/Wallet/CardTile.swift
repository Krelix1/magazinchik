import SwiftUI

/// A card in the grid. Layout gets quieter as columns get narrower: row → card → icon tile.
struct CardTile: View {
    let card: LoyaltyCard
    let density: GridDensity
    let isSuggested: Bool
    let distance: Double?

    private var radius: CGFloat {
        switch density {
        case .one, .two: 20
        case .three: 18
        case .four: 15
        }
    }

    var body: some View {
        content
            .overlay {
                if isSuggested {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.positive, lineWidth: 1.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSuggested, density != .one {
                    nearbyBadge
                }
            }
            .contentShape(.rect(cornerRadius: radius))
            .accessibilityElement(children: .combine)
            .accessibilityValue(isSuggested ? "Вы рядом с этим магазином" : "")
            .accessibilityHint("Удерживайте, чтобы переместить")
    }

    @ViewBuilder
    private var content: some View {
        switch density {
        case .one:
            CardRow(card: card, distance: distance, isSuggested: isSuggested)
        case .two:
            VStack(alignment: .leading, spacing: 0) {
                CardIcon(card: card, size: 40)
                Spacer(minLength: 16)
                Text(card.storeName)
                    .font(.headline)
                    .lineLimit(1)
                Text(distance.map(CardText.distance) ?? CardText.masked(card.number))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(isSuggested ? Theme.positive : .secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .surface(radius)
        case .three, .four:
            VStack(spacing: 8) {
                CardIcon(card: card, size: density == .three ? 46 : 38)
                Text(card.storeName)
                    .font(density == .three ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, density == .three ? 16 : 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .surface(radius)
        }
    }

    @ViewBuilder
    private var nearbyBadge: some View {
        if density == .two {
            Text("Рядом")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.positive, in: .capsule)
                .padding(10)
        } else {
            Image(systemName: "location.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 16, height: 16)
                .background(Theme.positive, in: .circle)
                .padding(6)
        }
    }
}
