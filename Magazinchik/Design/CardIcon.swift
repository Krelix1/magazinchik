import SwiftUI
import UIKit

/// The store "logo": a photo if one is already decoded, otherwise a symbol on a tinted rounded square.
/// Drawing this never reads the stored image bytes and never decodes them.
struct CardIcon: View {
    let symbolName: String
    let colorHex: String
    var logo: UIImage?
    var size: CGFloat = 44

    init(card: LoyaltyCard, size: CGFloat = 44, logo: UIImage? = nil) {
        self.symbolName = card.symbolName
        self.colorHex = card.colorHex
        self.logo = logo
        self.size = size
    }

    init(symbolName: String, colorHex: String, logo: UIImage? = nil, size: CGFloat = 44) {
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.logo = logo
        self.size = size
    }

    var body: some View {
        let color = Color(hex: colorHex)
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Group {
            if let logo {
                Image(uiImage: logo)
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

/// Decoded logos, filled off the main actor when a card changes. A tab switch only reads this.
final class LogoMemory: @unchecked Sendable {
    static let shared = LogoMemory()

    private let lock = NSLock()
    private var images: [UUID: UIImage] = [:]

    func replace(with payloads: [LogoPayload]) {
        var next: [UUID: UIImage] = [:]
        for payload in payloads {
            if let image = UIImage(data: payload.data) {
                next[payload.id] = image
            }
        }
        lock.lock()
        images = next
        lock.unlock()
    }

    func image(for id: UUID) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[id]
    }

    func snapshot() -> [UUID: UIImage] {
        lock.lock()
        defer { lock.unlock() }
        return images
    }
}

struct LogoPayload: Sendable {
    var id: UUID
    var data: Data
}
