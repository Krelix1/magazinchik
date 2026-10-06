import SwiftUI
import UIKit

/// The store "logo": a photo if the person picked one, otherwise a symbol on a tinted rounded square.
struct CardIcon: View {
    let symbolName: String
    let colorHex: String
    var logoData: Data?
    var size: CGFloat = 44

    init(card: LoyaltyCard, size: CGFloat = 44) {
        self.symbolName = card.symbolName
        self.colorHex = card.colorHex
        self.logoData = card.logoImageData
        self.size = size
    }

    init(symbolName: String, colorHex: String, logoData: Data? = nil, size: CGFloat = 44) {
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.logoData = logoData
        self.size = size
    }

    var body: some View {
        let color = Color(hex: colorHex)
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Group {
            if let logoData, let image = UIImage(data: logoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(color.opacity(0.18))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}
