import CoreLocation
import Foundation
import SwiftData
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

    @Test func santaAtTheStoreBeatsTheDemoCard() {
        let store = GeoPoint(latitude: 52.0646161, longitude: 23.7309056)
        let santa = UUID()
        let pyaterochka = UUID()
        let cards = [
            CardPlaces(cardID: pyaterochka, points: [GeoPoint(latitude: 55.76608, longitude: 37.605)]),
            CardPlaces(cardID: santa, points: [store])
        ]
        let snapshot = NearbyRanking.snapshot(for: cards, from: store, accuracy: 5)
        #expect(snapshot.suggestedID == santa)
        #expect(snapshot.order.first == santa)
    }

    @Test func approximateLocationNeverSuggests() {
        let cards = [CardPlaces(cardID: a, points: [north(30)])]
        #expect(NearbyRanking.snapshot(for: cards, from: home, accuracy: 3_000).suggestedID == nil)
    }

    @Test func storeAt640MetresStaysBackUntilAPinIsUnderfoot() {
        let user = GeoPoint(latitude: 52.07000, longitude: 23.73000)
        let store = GeoPoint(latitude: user.latitude + 640 / 111_195, longitude: user.longitude)
        let santa = UUID()
        let away = NearbyRanking.snapshot(for: [CardPlaces(cardID: santa, points: [store])], from: user, accuracy: 5)
        let metres = away.distance(for: santa)!
        #expect(metres > 600 && metres < 700)
        #expect(away.suggestedID == nil)
        #expect(NearbyStoreLabel.caption(name: "Санта - 54", metres: 640) == "Санта - 54 · 640 м")
        #expect(NearbyStoreLabel.caption(name: "Санта - 54", metres: metres)?.hasPrefix("Санта - 54") == true)
        #expect(!NearbyStoreLabel.isActivated(metres: metres, accuracy: 5))

        let standingOnPin = NearbyRanking.snapshot(for: [CardPlaces(cardID: santa, points: [user])], from: user, accuracy: 5)
        #expect(standingOnPin.suggestedID == santa)
        #expect(standingOnPin.order.first == santa)
        #expect(NearbyStoreLabel.isActivated(metres: 40, accuracy: 5))
    }

    @Test func cardBecomesFirstOnlyInsideAbout200Metres() {
        let user = GeoPoint(latitude: 52.07000, longitude: 23.73000)
        let santa = UUID()
        let other = UUID()
        let farStore = GeoPoint(latitude: user.latitude + 640 / 111_195, longitude: user.longitude)
        let closeStore = GeoPoint(latitude: user.latitude + 80 / 111_195, longitude: user.longitude)
        let away = NearbyRanking.snapshot(
            for: [
                CardPlaces(cardID: other, points: [closeStore]),
                CardPlaces(cardID: santa, points: [farStore])
            ],
            from: user,
            accuracy: 5
        )
        #expect(away.suggestedID == other)
        #expect(away.order.first == other)
        #expect(away.distance(for: santa)! > 600)
        #expect(!NearbyStoreLabel.isActivated(metres: away.distance(for: santa)!, accuracy: 5))

        let onlySanta = NearbyRanking.snapshot(
            for: [CardPlaces(cardID: santa, points: [farStore])],
            from: user,
            accuracy: 5
        )
        #expect(onlySanta.suggestedID == nil)
        let shown = NearbyStoreLabel.caption(name: "Санта - 54", metres: onlySanta.distance(for: santa))
        #expect(shown?.hasPrefix("Санта - 54") == true)
        #expect(shown != "Санта - 54 · 200 м")
    }
}

struct PlaceOrderingTests {
    let user = GeoPoint(latitude: 52.07000, longitude: 23.73000)

    func north(_ metres: Double) -> (latitude: Double, longitude: Double) {
        (user.latitude + metres / 111_195, user.longitude)
    }

    @Test func santaQueryPutsTheNearbyStoreAheadOfFartherNames() throws {
        let near = north(640)
        let far = north(7_000)
        let places = [
            PlaceDraft(name: "Санта 38", address: "", latitude: far.latitude, longitude: far.longitude),
            PlaceDraft(name: "Санта - 38", address: "", latitude: far.latitude, longitude: far.longitude + 0.002),
            PlaceDraft(name: "Санта", address: "точное имя далеко", latitude: far.latitude, longitude: far.longitude + 0.004),
            PlaceDraft(name: "Санта - 54", address: "Рабінавая вуліца 1А", latitude: near.latitude, longitude: near.longitude),
        ]
        let ordered = PlaceOrdering.ordered(places, query: "санта", near: user)
        #expect(ordered.first?.name == "Санта - 54")
        let names = ordered.map(\.name)
        let nearIndex = try #require(names.firstIndex(of: "Санта - 54"))
        let farSanta = try #require(names.firstIndex(of: "Санта"))
        #expect(farSanta > nearIndex)
        let farBranch = names.firstIndex(of: "Санта 38") ?? names.firstIndex(of: "Санта - 38")
        #expect(farBranch! > nearIndex)
    }

    @Test func duplicateNamesKeepTheClosest() {
        let near = north(640)
        let fartherSame = north(2_000)
        let places = [
            PlaceDraft(name: "Санта-54", address: "", latitude: fartherSame.latitude, longitude: fartherSame.longitude),
            PlaceDraft(name: "Санта - 54", address: "", latitude: near.latitude, longitude: near.longitude),
        ]
        let ordered = PlaceOrdering.ordered(places, query: "санта", near: user)
        #expect(ordered.count == 1)
        #expect(abs(ordered[0].latitude - near.latitude) < 0.00001)
    }
}

struct PlaceSearchTests {
    let user = GeoPoint(latitude: 52.07000, longitude: 23.73000)

    func north(_ metres: Double) -> (latitude: Double, longitude: Double) {
        (user.latitude + metres / 111_195, user.longitude)
    }

    @Test func santaMatchesNumberedStoreName() {
        #expect(CardText.place("Санта - 54", matchesBrand: "Санта"))
        #expect(CardText.place("Санта-54", matchesBrand: "Санта"))
    }

    @Test func santaRanksNearbyStoreAheadOfFartherNames() throws {
        let near = north(640)
        let far = north(7_000)
        let fartherExact = north(8_000)
        let nearby = [
            PlaceDraft(name: "Санта 38", address: "", latitude: far.latitude, longitude: far.longitude),
            PlaceDraft(name: "Санта - 54", address: "Рабінавая вуліца 1А", latitude: near.latitude, longitude: near.longitude),
        ]
        let addresses = [
            PlaceDraft(name: "Санта", address: "точное имя далеко", latitude: fartherExact.latitude, longitude: fartherExact.longitude),
            PlaceDraft(name: "Санта - 38", address: "", latitude: far.latitude, longitude: far.longitude + 0.01),
        ]
        let results = PlaceSearch.results(query: "санта", near: user, nearby: nearby, addresses: addresses)
        #expect(results.first?.name == "Санта - 54")
        let names = results.map(\.name)
        let nearIndex = try #require(names.firstIndex(of: "Санта - 54"))
        let exact = try #require(names.firstIndex(of: "Санта"))
        #expect(exact > nearIndex)
        let branch = try #require(names.firstIndex(of: "Санта 38") ?? names.firstIndex(of: "Санта - 38"))
        #expect(branch > nearIndex)
        let metres = user.distance(to: GeoPoint(latitude: results[0].latitude, longitude: results[0].longitude))
        #expect(metres > 600 && metres < 700)
    }

    @Test func failedOrEmptyNearbyLookupKeepsTheAddress() throws {
        let street = PlaceDraft(
            name: "Рабінавая вуліца",
            address: "Рабінавая вуліца 1А, Брест",
            latitude: 52.06462,
            longitude: 23.73036
        )
        let failed = PlaceSearch.results(query: "Рабінавая 1А", near: user, nearby: nil, addresses: [street])
        #expect(failed.contains { $0.address.contains("Рабінавая") && $0.address.contains("1А") })

        let empty = PlaceSearch.results(query: "Рабінавая 1А", near: user, nearby: [], addresses: [street])
        #expect(empty.map(\.address) == failed.map(\.address))

        let farStore = north(7_000)
        let junk = PlaceDraft(name: "Санта 38", address: "", latitude: farStore.latitude, longitude: farStore.longitude)
        let withJunk = PlaceSearch.results(query: "Рабінавая 1А", near: user, nearby: [junk], addresses: [street])
        let addressIndex = try #require(withJunk.firstIndex { $0.address.contains("1А") })
        #expect(withJunk.indices.contains(addressIndex))
    }
}

struct OpenStreetMapTests {
    let minsk = CLLocationCoordinate2D(latitude: 53.9, longitude: 27.56)

    @Test func santaPatternIsCaseInsensitive() {
        let pattern = OpenStreetMap.namePattern(for: "Санта")
        #expect(pattern == "^[Сс] *[Аа] *[Нн] *[Тт] *[Аа].*")
        let query = OpenStreetMap.overpassQuery(named: "Санта", near: minsk, radius: 5_000)
        #expect(query?.contains(#"node["name"~"^[Сс] *[Аа] *[Нн] *[Тт] *[Аа].*"](around:5000,53.90000,27.56000)"#) == true)
        #expect(query?.contains(#"way["name:ru"~"#) == true)
        #expect(OpenStreetMap.namePattern(for: "Я") == nil)
        #expect(CardText.place("САНТА", matchesBrand: "Санта"))
        #expect(CardText.place("санта", matchesBrand: "Санта"))
        #expect(CardText.place("Санта - 54", matchesBrand: "Санта"))
        #expect(CardText.place("Санта-54", matchesBrand: "Санта"))
        #expect(!CardText.place("Пиво", matchesBrand: "Санта"))
    }

    @Test func santaMatchesNearbyNamedPlacesOnly() throws {
        let json = """
        {"elements":[
          {"type":"node","id":1,"lat":53.901,"lon":27.561,"tags":{"name":"Санта","addr:street":"пр-т Независимости","addr:housenumber":"1"}},
          {"type":"way","id":2,"center":{"lat":53.91,"lon":27.56},"tags":{"name:ru":"САНТА"}},
          {"type":"way","id":6,"center":{"lat":52.06462,"lon":23.73091},"tags":{"name":"Санта - 54","shop":"supermarket"}},
          {"type":"node","id":3,"lat":53.902,"lon":27.562,"tags":{"name":"Пиво"}},
          {"type":"node","id":4,"lat":55.75,"lon":37.62,"tags":{"name":"Санта"}},
          {"type":"node","id":5,"lat":53.901,"lon":27.561,"tags":{"name":"Санта"}}
        ]}
        """.data(using: .utf8)!
        let places = try OpenStreetMap.places(matching: "Санта", near: minsk, radius: 5_000, overpassData: json)
        #expect(places.map(\.name) == ["Санта", "САНТА"])
        #expect(places[0].address.contains("Независимости"))
        let brest = CLLocationCoordinate2D(latitude: 52.0646161, longitude: 23.7309056)
        let atStore = try OpenStreetMap.places(matching: "Санта", near: brest, radius: 5_000, overpassData: json)
        #expect(atStore.map(\.name) == ["Санта - 54"])
    }

    @Test func overpassFailureIsNotAnEmptyResult() throws {
        let timeout = Data(#"{"remark":"runtime error: Query timed out"}"#.utf8)
        #expect(throws: OpenStreetMapError.self) {
            try OpenStreetMap.places(matching: "Санта", near: minsk, radius: 5_000, overpassData: timeout)
        }
        let empty = try #require(try? OpenStreetMap.places(
            matching: "Санта",
            near: minsk,
            radius: 5_000,
            overpassData: Data(#"{"elements":[]}"#.utf8)
        ))
        #expect(empty.isEmpty)
        let remarkedEmpty = Data(#"{"remark":"runtime error: Query timed out","elements":[]}"#.utf8)
        #expect(throws: OpenStreetMapError.self) {
            try OpenStreetMap.places(matching: "Санта", near: minsk, radius: 5_000, overpassData: remarkedEmpty)
        }
    }
}

struct NearbyCardsServiceTests {
    let origin = CLLocationCoordinate2D(latitude: 52.10, longitude: 23.70)
    let card = UUID()
    let other = UUID()

    func place(cardID: UUID, metresNorth: Double, id: String) -> ProximityStore {
        ProximityStore(
            id: id,
            cardID: cardID,
            latitude: origin.latitude + metresNorth / 111_195,
            longitude: origin.longitude
        )
    }

    func fix(metresNorth: Double, accuracy: CLLocationAccuracy) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: origin.latitude + metresNorth / 111_195,
                longitude: origin.longitude
            ),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 0,
            timestamp: Date()
        )
    }

    @Test func enterAndExitUseDifferentRadii() {
        let service = NearbyCardsService()
        service.setStores([place(cardID: card, metresNorth: 0, id: "store")])

        #expect(service.update(userLocation: fix(metresNorth: 110, accuracy: 10)).isEmpty)

        let entered = service.update(userLocation: fix(metresNorth: 40, accuracy: 10))
        #expect(entered == [card])

        let stillInside = service.update(userLocation: fix(metresNorth: 130, accuracy: 10))
        #expect(stillInside == [card])

        let left = service.update(userLocation: fix(metresNorth: 200, accuracy: 10))
        #expect(left.isEmpty)
    }

    @Test func severalStoresOfOneCardCountOnce() {
        let service = NearbyCardsService()
        service.setStores([
            place(cardID: card, metresNorth: 10, id: "a"),
            place(cardID: card, metresNorth: 20, id: "b"),
            place(cardID: card, metresNorth: 30, id: "c"),
        ])
        let nearby = service.update(userLocation: fix(metresNorth: 0, accuracy: 5))
        #expect(nearby == [card])
        #expect(nearby.count == 1)
    }

    @Test func moveUnder30MetresDoesNotUpdate() {
        let service = NearbyCardsService()
        service.setStores([
            place(cardID: card, metresNorth: 0, id: "here"),
            place(cardID: other, metresNorth: 115, id: "ahead"),
        ])
        let first = service.update(userLocation: fix(metresNorth: 0, accuracy: 5))
        #expect(first == [card])

        let nudged = service.update(userLocation: fix(metresNorth: 20, accuracy: 5))
        #expect(nudged == [card])
        #expect(!nudged.contains(other))
    }

    @Test func inaccurateFixDoesNotFlipTheCard() {
        let service = NearbyCardsService()
        service.setStores([place(cardID: card, metresNorth: 0, id: "store")])

        let shown = service.update(userLocation: fix(metresNorth: 0, accuracy: 10))
        #expect(shown == [card])

        let sloppy = service.update(userLocation: fix(metresNorth: 500, accuracy: 180))
        #expect(sloppy == [card])

        let fresh = NearbyCardsService()
        fresh.setStores([place(cardID: card, metresNorth: 0, id: "store")])
        #expect(fresh.update(userLocation: fix(metresNorth: 0, accuracy: 180)).isEmpty)
    }
}

@MainActor
struct StoreCacheTests {
    @Test func knownBrandInThisCityIsNotFetchedAgain() {
        let santa = CardText.normalizedName("Санта")
        #expect(BrandCityLookup.shouldFetch(cachedBrandKeys: [], brand: "Санта"))
        #expect(!BrandCityLookup.shouldFetch(cachedBrandKeys: [santa], brand: "санта"))
        #expect(BrandCityLookup.shouldFetch(cachedBrandKeys: [santa], brand: "Магнит"))
        #expect(!BrandCityLookup.shouldFetch(cachedBrandKeys: [], brand: " "))
    }

    @Test func emptyLookupDoesNotCacheOrDropTheManualPin() throws {
        let context = AppModelStore.container.mainContext
        let card = LoyaltyCard(storeName: "Санта", number: "4600721000011", barcodeKind: .ean13)
        context.insert(card)
        var draft = CardDraft()
        draft.storeName = "Санта"
        draft.number = "4600721000011"
        draft.kind = .ean13
        draft.places = [PlaceDraft(name: "Санта", address: "Отмечено на месте", latitude: 52.065764, longitude: 23.723545)]
        draft.apply(to: card, in: context)
        try context.save()

        let here = CLLocation(latitude: 52.065764, longitude: 23.723545)
        StoreLocator.apply(matches: [], to: card, near: here, in: context)
        #expect(card.storesSearchedAt == nil)
        #expect(card.locations.contains { $0.isUserDefined && abs($0.latitude - 52.065764) < 0.000001 })

        let user = GeoPoint(latitude: 52.065764, longitude: 23.723545)
        let snapshot = NearbyRanking.snapshot(for: [card.places], from: user, accuracy: 5)
        #expect(snapshot.suggestedID == card.id)
        #expect(snapshot.order.first == card.id)
    }

    @Test func osmHitFartherThan200mDoesNotPromoteButTheManualPinDoes() throws {
        let context = AppModelStore.container.mainContext
        let card = LoyaltyCard(storeName: "Санта", number: "4600721000011", barcodeKind: .ean13)
        context.insert(card)
        let here = CLLocation(latitude: 52.065764, longitude: 23.723545)
        let user = GeoPoint(latitude: here.coordinate.latitude, longitude: here.coordinate.longitude)
        let supermarket = PlaceDraft(name: "Санта", address: "", latitude: 52.06960, longitude: 23.73611)
        let metres = user.distance(to: GeoPoint(latitude: supermarket.latitude, longitude: supermarket.longitude))
        #expect(metres > NearbyRanking.suggestionRadius)
        #expect(metres < 1_200)

        StoreLocator.apply(matches: [supermarket], to: card, near: here, in: context)
        let osmOnly = NearbyRanking.snapshot(for: [card.places], from: user, accuracy: 5)
        #expect(card.storesSearchedAt != nil)
        #expect(osmOnly.suggestedID == nil)

        let pin = StoreLocation(name: "Санта", address: "Отмечено на месте", latitude: user.latitude, longitude: user.longitude, isUserDefined: true)
        pin.card = card
        context.insert(pin)
        StoreLocator.apply(matches: [supermarket], to: card, near: here, in: context)
        let withPin = NearbyRanking.snapshot(for: [card.places], from: user, accuracy: 5)
        #expect(card.locations.contains { $0.isUserDefined })
        #expect(withPin.suggestedID == card.id)
    }
}
