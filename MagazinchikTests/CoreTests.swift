import Foundation
import Testing
@testable import Magazinchik

struct EANTests {
    @Test func checksum() {
        #expect(EANEncoder.hasValidChecksum("4006381333931"))
        #expect(EANEncoder.hasValidChecksum("4607001771586"))
        #expect(EANEncoder.hasValidChecksum("96385074"))
        #expect(!EANEncoder.hasValidChecksum("4006381333932"))
    }

    @Test func derivedTables() {
        #expect(EANEncoder.right(0) == "1110010")
        #expect(EANEncoder.leftEven(0) == "0100111")
        #expect(EANEncoder.right(9) == "1110100")
        #expect(EANEncoder.leftEven(9) == "0010111")
    }

    @Test func moduleCounts() throws {
        let ean13 = try #require(EANEncoder.modules(for: "4006381333931"))
        #expect(ean13.count == 95)
        let ean8 = try #require(EANEncoder.modules(for: "96385074"))
        #expect(ean8.count == 67)
        #expect(EANEncoder.modules(for: "4006381333932") == nil)
    }

    @Test func knownPattern() throws {
        // Leading digit 4 selects LGLLGG parity; digit "0" in position 2 is G-coded.
        let modules = try #require(EANEncoder.modules(for: "4006381333931"))
        let bits = String(modules.map { $0 ? "1" : "0" })
        #expect(bits.hasPrefix("101" + "0001101" + "0100111"))
        // Right half ends with digits 3 and 1 (R-coded), then the end guard.
        #expect(bits.hasSuffix("1000010" + "1100110" + "101"))
    }
}

struct BarcodeKindTests {
    @Test func guess() {
        #expect(BarcodeKind.guess(for: "4006381333931") == .ean13)
        #expect(BarcodeKind.guess(for: "96385074") == .ean8)
        #expect(BarcodeKind.guess(for: "1234567") == .code128)
        #expect(BarcodeKind.guess(for: "https://example.com/card?id=42&user=very-long-identifier") == .qr)
    }

    @Test func problems() {
        #expect(BarcodeKind.ean13.problem(with: "4006381333931") == nil)
        #expect(BarcodeKind.ean13.problem(with: "40063813") != nil)
        #expect(BarcodeKind.code128.problem(with: "Карта") != nil)
        #expect(BarcodeKind.qr.problem(with: "Карта") == nil)
        #expect(BarcodeKind.none.problem(with: "") != nil)
    }
}

struct CardTextTests {
    @Test func picksCardNumberOverPhone() {
        let lines = ["Пятёрочка", "Выручай-карта", "Тел. 8 800 555 55 05", "4006 3813 3393 1"]
        #expect(CardText.bestNumber(in: lines) == "4006381333931")
    }

    @Test func noNumber() {
        #expect(CardText.bestNumber(in: ["Скидка 5%", "до 12.2027"]) == nil)
    }

    @Test func digitRuns() {
        #expect(CardText.digitRuns(in: "№ 2775 0011 2233") == ["277500112233"])
        #expect(CardText.digitRuns(in: "12  34") == [])
    }

    @Test func formatting() {
        #expect(CardText.grouped("4006381333931") == "4006 3813 3393 1")
        #expect(CardText.grouped("AB12") == "AB12")
        #expect(CardText.masked("4006381333931") == "•• 3931")
        #expect(CardText.distance(37) == "40 м")
        #expect(CardText.distance(4) == "10 м")
        #expect(CardText.distance(1_840) == "1,8 км")
        #expect(CardText.distance(12_400) == "12 км")
    }

    @Test func russianPlural() {
        #expect(CardText.cardCount(1) == "1 карта")
        #expect(CardText.cardCount(3) == "3 карты")
        #expect(CardText.cardCount(5) == "5 карт")
        #expect(CardText.cardCount(11) == "11 карт")
        #expect(CardText.cardCount(22) == "22 карты")
    }

    @Test func brandMatching() {
        #expect(CardText.place("Пятерочка", matchesBrand: "Пятёрочка"))
        #expect(CardText.place("ВкусВилл, Тверская 12", matchesBrand: "Вкусвилл"))
        #expect(CardText.place("Магнит у дома", matchesBrand: "Магнит"))
        #expect(!CardText.place("Аптека 36,6", matchesBrand: "Магнит"))
    }
}

struct OrderingTests {
    @Test func moves() {
        #expect(CardOrdering.move(1, onto: 3, in: [1, 2, 3, 4]) == [2, 3, 1, 4])
        #expect(CardOrdering.move(4, onto: 2, in: [1, 2, 3, 4]) == [1, 4, 2, 3])
        #expect(CardOrdering.moveToFront(3, in: [1, 2, 3]) == [3, 1, 2])
        #expect(CardOrdering.moveToBack(1, in: [1, 2, 3]) == [2, 3, 1])
        #expect(CardOrdering.move(9, onto: 2, in: [1, 2]) == [1, 2])
    }
}

struct NearbyRankingTests {
    let home = GeoPoint(latitude: 55.7558, longitude: 37.6173)
    let a = UUID(), b = UUID(), c = UUID()

    /// Roughly `metres` north of `home`.
    func north(_ metres: Double) -> GeoPoint {
        GeoPoint(latitude: home.latitude + metres / 111_195, longitude: home.longitude)
    }

    @Test func distance() {
        #expect(abs(home.distance(to: north(1000)) - 1000) < 2)
    }

    @Test func noLocationKeepsManualOrder() {
        let snapshot = NearbyRanking.snapshot(for: [CardPlaces(cardID: a, points: []), CardPlaces(cardID: b, points: [home])], from: nil)
        #expect(snapshot.order == [a, b])
        #expect(snapshot.suggestedID == nil)
    }

    @Test func suggestsClosestWithinRadius() {
        let cards = [
            CardPlaces(cardID: a, points: [north(900)]),
            CardPlaces(cardID: b, points: []),
            CardPlaces(cardID: c, points: [north(5_000), north(60)]),
        ]
        let snapshot = NearbyRanking.snapshot(for: cards, from: home, accuracy: 10)
        #expect(snapshot.order == [c, a, b])
        #expect(snapshot.suggestedID == c)
        #expect(abs(snapshot.distance(for: c)! - 60) < 1)
    }

    @Test func nothingCloseEnough() {
        let snapshot = NearbyRanking.snapshot(for: [CardPlaces(cardID: a, points: [north(400)])], from: home, accuracy: 10)
        #expect(snapshot.suggestedID == nil)
    }

    @Test func hysteresisKeepsCurrentSuggestion() {
        let cards = [CardPlaces(cardID: a, points: [north(260)])]
        #expect(NearbyRanking.snapshot(for: cards, from: home, accuracy: 10).suggestedID == nil)
        #expect(NearbyRanking.snapshot(for: cards, from: home, accuracy: 10, current: a).suggestedID == a)
    }

    @Test func closerStoreWinsOverStickySuggestion() {
        let cards = [CardPlaces(cardID: a, points: [north(250)]), CardPlaces(cardID: b, points: [north(30)])]
        #expect(NearbyRanking.snapshot(for: cards, from: home, accuracy: 10, current: a).suggestedID == b)
    }

    @Test func approximateLocationNeverSuggests() {
        let cards = [CardPlaces(cardID: a, points: [north(30)])]
        #expect(NearbyRanking.snapshot(for: cards, from: home, accuracy: 3_000).suggestedID == nil)
    }
}
