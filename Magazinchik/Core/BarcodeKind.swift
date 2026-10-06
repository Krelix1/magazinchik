import Foundation

enum BarcodeKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case ean13
    case ean8
    case code128
    case qr
    case pdf417
    case aztec
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .code128: "Code 128"
        case .qr: "QR-код"
        case .pdf417: "PDF417"
        case .aztec: "Aztec"
        case .none: "Без кода"
        }
    }

    var isTwoDimensional: Bool {
        self == .qr || self == .aztec
    }

    var isNumericOnly: Bool {
        self == .ean13 || self == .ean8
    }

    /// Russian explanation of why `number` can't be encoded, or `nil` when it can.
    func problem(with number: String) -> String? {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Введите номер карты" }
        switch self {
        case .ean13, .ean8:
            let length = self == .ean13 ? 13 : 8
            guard trimmed.allSatisfy(\.isASCIIDigit) else { return "\(title) состоит только из цифр" }
            guard trimmed.count == length else { return "Для \(title) нужно \(length) цифр" }
            guard EANEncoder.hasValidChecksum(trimmed) else { return "Последняя цифра не сходится — проверьте номер" }
            return nil
        case .code128:
            guard trimmed.allSatisfy({ $0.isASCII }) else { return "Code 128 поддерживает только латиницу и цифры" }
            return nil
        case .qr, .pdf417, .aztec, .none:
            return nil
        }
    }

    /// Best guess for a payload typed by hand or recognised by OCR.
    static func guess(for payload: String) -> BarcodeKind {
        let digits = payload.filter { !$0.isWhitespace }
        if digits.allSatisfy(\.isASCIIDigit) {
            if digits.count == 13, EANEncoder.hasValidChecksum(digits) { return .ean13 }
            if digits.count == 8, EANEncoder.hasValidChecksum(digits) { return .ean8 }
        }
        if payload.allSatisfy({ $0.isASCII }), payload.count <= 40 { return .code128 }
        return .qr
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
