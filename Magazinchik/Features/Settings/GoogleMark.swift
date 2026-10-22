import SwiftUI

/// The four-color Google G. Drawn from the sign-in mark, not an SF Symbol.
struct GoogleMark: View {
    static let blue = "4285F4"
    static let red = "EA4335"
    static let yellow = "FBBC05"
    static let green = "34A853"

    var side: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let parts = [
                (Self.redPath, Self.red),
                (Self.bluePath, Self.blue),
                (Self.yellowPath, Self.yellow),
                (Self.greenPath, Self.green),
            ]
            for (source, hex) in parts {
                let path = GoogleLogoPath.shape(source, in: rect)
                context.fill(path, with: .color(Color(hex: hex)))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    static let redPath = "M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"
    static let bluePath = "M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"
    static let yellowPath = "M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"
    static let greenPath = "M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"
}

enum GoogleLogoPath {
    /// `source` is an SVG path in a 48×48 box, scaled into `rect`.
    static func shape(_ source: String, in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 48
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
        return path(from: source).applying(transform)
    }

    static func path(from source: String) -> Path {
        var path = Path()
        var index = source.startIndex
        var active: Character?
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var cubicControl: CGPoint?

        func skipSeparators() {
            while index < source.endIndex {
                let character = source[index]
                if character == "," || character.isWhitespace {
                    index = source.index(after: index)
                } else {
                    break
                }
            }
        }

        func readNumber() -> CGFloat {
            skipSeparators()
            guard index < source.endIndex else { return 0 }
            var token = ""
            let sign = source[index]
            if sign == "+" || sign == "-" {
                token.append(sign)
                index = source.index(after: index)
            }
            var sawDot = false
            while index < source.endIndex {
                let character = source[index]
                if character.isNumber {
                    token.append(character)
                    index = source.index(after: index)
                } else if character == ".", !sawDot {
                    sawDot = true
                    token.append(character)
                    index = source.index(after: index)
                } else {
                    break
                }
            }
            return CGFloat(Double(token) ?? 0)
        }

        func readPoint(relative: Bool) -> CGPoint {
            let x = readNumber()
            let y = readNumber()
            if relative {
                return CGPoint(x: current.x + x, y: current.y + y)
            }
            return CGPoint(x: x, y: y)
        }

        func reflectedControl() -> CGPoint {
            guard let cubicControl else { return current }
            return CGPoint(x: current.x * 2 - cubicControl.x, y: current.y * 2 - cubicControl.y)
        }

        while index < source.endIndex {
            skipSeparators()
            guard index < source.endIndex else { break }
            if source[index].isLetter {
                active = source[index]
                index = source.index(after: index)
            }
            guard let command = active else { break }

            switch command {
            case "M":
                let point = readPoint(relative: false)
                path.move(to: point)
                current = point
                subpathStart = point
                cubicControl = nil
                active = "L"
            case "m":
                let point = readPoint(relative: true)
                path.move(to: point)
                current = point
                subpathStart = point
                cubicControl = nil
                active = "l"
            case "L":
                let point = readPoint(relative: false)
                path.addLine(to: point)
                current = point
                cubicControl = nil
            case "l":
                let point = readPoint(relative: true)
                path.addLine(to: point)
                current = point
                cubicControl = nil
            case "H":
                current.x = readNumber()
                path.addLine(to: current)
                cubicControl = nil
            case "h":
                current.x += readNumber()
                path.addLine(to: current)
                cubicControl = nil
            case "V":
                current.y = readNumber()
                path.addLine(to: current)
                cubicControl = nil
            case "v":
                current.y += readNumber()
                path.addLine(to: current)
                cubicControl = nil
            case "C":
                let control1 = readPoint(relative: false)
                let control2 = readPoint(relative: false)
                let end = readPoint(relative: false)
                path.addCurve(to: end, control1: control1, control2: control2)
                cubicControl = control2
                current = end
            case "c":
                let control1 = readPoint(relative: true)
                let control2 = readPoint(relative: true)
                let end = readPoint(relative: true)
                path.addCurve(to: end, control1: control1, control2: control2)
                cubicControl = control2
                current = end
            case "S":
                let control1 = reflectedControl()
                let control2 = readPoint(relative: false)
                let end = readPoint(relative: false)
                path.addCurve(to: end, control1: control1, control2: control2)
                cubicControl = control2
                current = end
            case "s":
                let control1 = reflectedControl()
                let control2 = readPoint(relative: true)
                let end = readPoint(relative: true)
                path.addCurve(to: end, control1: control1, control2: control2)
                cubicControl = control2
                current = end
            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
                cubicControl = nil
                active = nil
            default:
                active = nil
            }
        }
        return path
    }
}
