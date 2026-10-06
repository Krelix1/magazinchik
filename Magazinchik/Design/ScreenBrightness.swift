import UIKit

/// Full brightness while a code is on screen; the previous level comes back when it leaves or the app goes to background.
@MainActor
enum ScreenBrightness {
    private static var savedLevel: CGFloat?

    private static var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }

    static func boost() {
        guard savedLevel == nil, let screen else { return }
        savedLevel = screen.brightness
        screen.brightness = 1
    }

    static func restore() {
        guard let level = savedLevel, let screen else { return }
        screen.brightness = level
        savedLevel = nil
    }
}
