import Foundation

/// EAN-13 / EAN-8 encoder. Core Image has no EAN generator, and most Russian loyalty cards use EAN-13.
enum EANEncoder {
    private static let leftOdd: [String] = [
        "0001101", "0011001", "0010011", "0111101", "0100011",
        "0110001", "0101111", "0111011", "0110111", "0001011",
    ]

    /// Parity of the six left-hand digits, selected by the first (implicit) digit of an EAN-13.
    private static let parity: [String] = [
        "LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
        "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL",
    ]

    static func checksumDigit(for data: [Int]) -> Int {
        var sum = 0
        for (offset, digit) in data.reversed().enumerated() {
            sum += digit * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    static func hasValidChecksum(_ code: String) -> Bool {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == code.count, digits.count >= 2 else { return false }
        return checksumDigit(for: Array(digits.dropLast())) == digits.last
    }

    /// Bar modules (`true` = black), without quiet zones. `nil` if the code is not a valid EAN.
    static func modules(for code: String) -> [Bool]? {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == code.count, hasValidChecksum(code) else { return nil }

        var pattern = "101"
        switch digits.count {
        case 13:
            let parityPattern = Array(parity[digits[0]])
            for index in 1...6 {
                pattern += parityPattern[index - 1] == "L" ? leftOdd[digits[index]] : leftEven(digits[index])
            }
            pattern += "01010"
            for index in 7...12 { pattern += right(digits[index]) }
        case 8:
            for index in 0...3 { pattern += leftOdd[digits[index]] }
            pattern += "01010"
            for index in 4...7 { pattern += right(digits[index]) }
        default:
            return nil
        }
        pattern += "101"
        return pattern.map { $0 == "1" }
    }

    static func right(_ digit: Int) -> String {
        String(leftOdd[digit].map { $0 == "1" ? "0" : "1" })
    }

    static func leftEven(_ digit: Int) -> String {
        String(right(digit).reversed())
    }
}
