import Foundation

enum CardText {
    /// Picks the most likely card number from OCR lines of a card photo.
    static func bestNumber(in lines: [String]) -> String? {
        var best: (number: String, score: Int)?
        for line in lines {
            let lowered = line.lowercased()
            let looksLikePhone = lowered.contains("+7") || lowered.contains("тел") || lowered.contains("8 800") || lowered.contains("8-800")
            for candidate in digitRuns(in: line) {
                var score = candidate.count
                if (candidate.count == 13 || candidate.count == 8), EANEncoder.hasValidChecksum(candidate) { score += 10 }
                if looksLikePhone || candidate.hasPrefix("8800") { score -= 20 }
                if best == nil || score > best!.score { best = (candidate, score) }
            }
        }
        guard let best, best.score > 0 else { return nil }
        return best.number
    }

    /// Runs of 6–20 digits, allowing single spaces or dashes between groups ("4006 3813 3393 1").
    static func digitRuns(in line: String) -> [String] {
        var runs: [String] = []
        var current = ""
        var pendingSeparator = false
        func flush() {
            if (6...20).contains(current.count) { runs.append(current) }
            current = ""
            pendingSeparator = false
        }
        for character in line {
            if character.isASCIIDigit {
                current.append(character)
                pendingSeparator = false
            } else if (character == " " || character == "-" || character == "\u{00A0}"), !current.isEmpty, !pendingSeparator {
                pendingSeparator = true
            } else {
                flush()
            }
        }
        flush()
        return runs
    }

    /// "4006381333931" → "4006 3813 3393 1"; non-numeric codes are returned as is.
    static func grouped(_ number: String) -> String {
        guard number.count > 6, number.allSatisfy(\.isASCIIDigit) else { return number }
        var result = ""
        for (index, character) in number.enumerated() {
            if index > 0, index.isMultiple(of: 4) { result.append(" ") }
            result.append(character)
        }
        return result
    }

    /// "•• 3931" — short form for small tiles.
    static func masked(_ number: String) -> String {
        guard number.count > 4 else { return number }
        return "•• " + number.suffix(4)
    }

    /// "1 карта", "3 карты", "11 карт".
    static func cardCount(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        let word: String
        if mod10 == 1, mod100 != 11 {
            word = "карта"
        } else if (2...4).contains(mod10), !(12...14).contains(mod100) {
            word = "карты"
        } else {
            word = "карт"
        }
        return "\(count) \(word)"
    }

    /// "40 м", "850 м", "1,8 км", "12 км".
    static func distance(_ metres: Double) -> String {
        if metres < 995 {
            return "\(max(10, Int((metres / 10).rounded()) * 10)) м"
        }
        let kilometres = metres / 1000
        if kilometres < 10 {
            let tenths = Int((kilometres * 10).rounded())
            return "\(tenths / 10),\(tenths % 10) км"
        }
        return "\(Int(kilometres.rounded())) км"
    }

    /// Lowercased, without diacritics (ё → е) and punctuation, for comparing brand names.
    static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Whether a map search result named `placeName` belongs to the brand `brand`.
    static func place(_ placeName: String, matchesBrand brand: String) -> Bool {
        let place = normalizedName(placeName)
        let brand = normalizedName(brand)
        guard !place.isEmpty, brand.count >= 2 else { return false }
        return place.contains(brand) || (place.count >= 4 && brand.contains(place))
    }
}

enum CardOrdering {
    /// Moves `item` to the index currently held by `target`.
    static func move<ID: Equatable>(_ item: ID, onto target: ID, in order: [ID]) -> [ID] {
        guard item != target,
              let from = order.firstIndex(of: item),
              let to = order.firstIndex(of: target) else { return order }
        var result = order
        result.remove(at: from)
        result.insert(item, at: to)
        return result
    }

    static func moveToFront<ID: Equatable>(_ item: ID, in order: [ID]) -> [ID] {
        guard let first = order.first else { return order }
        return move(item, onto: first, in: order)
    }

    static func moveToBack<ID: Equatable>(_ item: ID, in order: [ID]) -> [ID] {
        guard let last = order.last else { return order }
        return move(item, onto: last, in: order)
    }
}

enum GridDensity: Int, CaseIterable, Identifiable, Sendable {
    case one = 1, two, three, four

    var id: Int { rawValue }
    var columns: Int { rawValue }

    var symbolName: String {
        switch self {
        case .one: "rectangle.grid.1x2"
        case .two: "square.grid.2x2"
        case .three: "square.grid.3x3"
        case .four: "square.grid.4x3.fill"
        }
    }

    var accessibilityName: String {
        switch self {
        case .one: "Одна колонка"
        case .two: "Две колонки"
        case .three: "Три колонки"
        case .four: "Четыре колонки"
        }
    }
}
