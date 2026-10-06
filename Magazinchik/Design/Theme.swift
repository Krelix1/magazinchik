import SwiftUI
import UIKit

/// Qalta-like: near-black canvas, flat surfaces with a whisper of contrast, color only as small accents.
/// Liquid Glass is reserved for controls (tab bar, buttons) so it reads as the interactive layer.
enum Theme {
    static let background = Color(light: 0xF2F2F5, dark: 0x0A0A0A)
    static let surface = Color(light: 0xFFFFFF, dark: 0x161618)
    static let surfaceRaised = Color(light: 0xE8E8ED, dark: 0x202023)
    static let positive = Color(hex: "30D158")

    static let cornerRadius: CGFloat = 22
    static let padding: CGFloat = 20

    /// Store accent colors: everyday orange, groceries yellow, food red, green, digital blue/purple, plus neutrals.
    static let palette = [
        "30D158", "FF9F0A", "FFD60A", "FF453A", "FF375F",
        "BF5AF2", "0A84FF", "64D2FF", "AC8E68", "8E8E93",
    ]

    static let paletteNames = [
        "Зелёный", "Оранжевый", "Жёлтый", "Красный", "Розовый",
        "Фиолетовый", "Синий", "Голубой", "Коричневый", "Серый",
    ]

    static func colorName(_ hex: String) -> String {
        Theme.palette.firstIndex(of: hex).map { paletteNames[$0] } ?? "Свой цвет"
    }

    static let symbols = [
        "cart.fill", "basket.fill", "bag.fill", "cup.and.saucer.fill",
        "fork.knife", "cross.case.fill", "fuelpump.fill", "tshirt.fill",
        "pawprint.fill", "book.fill", "gift.fill", "sparkles",
        "house.fill", "hammer.fill", "gamecontroller.fill", "airplane",
    ]

    static let spring = Animation.spring(response: 0.35, dampingFraction: 1)
    static let bouncySpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x8E8E93
        self.init(uiColor: UIColor(rgb: value))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Flat content surface. Not glass: cards are content, glass is for controls.
    func surface(_ radius: CGFloat = Theme.cornerRadius, color: Color = Theme.surface) -> some View {
        background(color, in: .rect(cornerRadius: radius, style: .continuous))
    }

    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

/// Section caption above a group, like "Ещё рядом".
struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing { Text(trailing) }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
