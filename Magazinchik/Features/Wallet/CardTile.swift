import SwiftUI

/// A card in the grid. Layout gets quieter as columns get narrower: row → card → icon tile.
struct CardTile: View {
    let card: LoyaltyCard
    let density: GridDensity
    let isSuggested: Bool
    let distance: Double?
    var placeName: String? = nil
    var logo: UIImage? = nil

    private var radius: CGFloat {
        switch density {
        case .one, .two: 20
        case .three: 18
        case .four: 15
        }
    }

    var body: some View {
        content
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
            CardRow(card: card, distance: distance, placeName: placeName, logo: logo, isSuggested: isSuggested)
        case .two:
            VStack(alignment: .leading, spacing: 0) {
                CardIcon(card: card, size: 40, logo: logo)
                Spacer(minLength: 16)
                Text(card.storeName)
                    .font(.headline)
                    .lineLimit(1)
                if let placeName, !placeName.isEmpty {
                    Text(placeName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                    if let distance {
                        Text(CardText.distance(distance))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else if !card.note.isEmpty {
                    Text(card.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                } else if let distance {
                    Text(CardText.distance(distance))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .surface(radius)
        case .three, .four:
            VStack(spacing: 8) {
                CardIcon(card: card, size: density == .three ? 46 : 38, logo: logo)
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
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surfaceRaised, in: .capsule)
                .padding(10)
        } else {
            Image(systemName: "location.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(Theme.surfaceRaised, in: .circle)
                .padding(6)
        }
    }
}
