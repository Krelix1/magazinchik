import Foundation
import SwiftData
import Testing
@testable import Magazinchik

@MainActor
struct CardSyncTests {
    @Test func payloadIncludesCustomPlacesAndSkipsMapStoresAndImages() throws {
        let context = AppModelStore.container.mainContext
        let card = LoyaltyCard(storeName: "Санта", number: "4600721000011", barcodeKind: .ean13, colorHex: "FFD60A", symbolName: "cart.fill", note: "у кассы", position: 2)
        let logo = Data("logo-bytes-DEADBEEF".utf8)
        card.logoImageData = logo
        context.insert(card)

        let mine = StoreLocation(name: "У дома", address: "Ленина, 1", latitude: 52.097621, longitude: 23.734455, isUserDefined: true)
        mine.card = card
        context.insert(mine)
        let catalog = StoreLocation(name: "OSM-СКЛАД-НЕ-СИНХ", address: "osm-catalog-do-not-sync", latitude: 41.25, longitude: 2.5, isUserDefined: false)
        catalog.card = card
        context.insert(catalog)
        try context.save()
        defer {
            context.delete(card)
            try? context.save()
        }

        #expect(card.automaticPlaces.count == 1)
        #expect(card.userPlaces.count == 1)

        let record = CardSyncRecord(card)
        #expect(record.places == [CardSyncPlace(name: "У дома", address: "Ленина, 1", latitude: 52.097621, longitude: 23.734455)])
        #expect(record.storeName == "Санта")
        #expect(record.barcodeKind == BarcodeKind.ean13.rawValue)
        #expect(record.barcodePayload == "4600721000011")
        #expect(record.sortOrder == 2)
        #expect(record.note == "у кассы")
        #expect(record.colorHex == "FFD60A")
        #expect(record.symbolName == "cart.fill")

        let data = try JSONEncoder().encode(record.document)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == CardSyncRecord.fieldNames)

        let places = try #require(object["places"] as? [[String: Any]])
        #expect(places.count == 1)
        #expect(Set(places[0].keys) == CardSyncRecord.placeFieldNames)
        #expect(places[0]["name"] as? String == "У дома")
        #expect(places[0]["address"] as? String == "Ленина, 1")

        let text = String(decoding: data, as: UTF8.self)
        let logoBase64 = logo.base64EncodedString()
        #expect(!text.contains("OSM-СКЛАД-НЕ-СИНХ"))
        #expect(!text.contains("osm-catalog-do-not-sync"))
        #expect(!text.contains("41.25"))
        #expect(!text.contains("logo-bytes-DEADBEEF"))
        #expect(!text.contains(logoBase64))
        #expect(object["logoImageData"] == nil)
        #expect(object["image"] == nil)
        #expect(object["photo"] == nil)
    }

    @Test func applyingRemoteKeepsLocalPhotoAndMapStores() throws {
        let context = AppModelStore.container.mainContext
        let card = LoyaltyCard(storeName: "Санта", number: "4600721000011", barcodeKind: .ean13)
        let logo = Data("logo-bytes-DEADBEEF".utf8)
        card.logoImageData = logo
        context.insert(card)
        let catalog = StoreLocation(name: "OSM-СКЛАД-НЕ-СИНХ", address: "osm-catalog-do-not-sync", latitude: 41.25, longitude: 2.5, isUserDefined: false)
        catalog.card = card
        context.insert(catalog)
        try context.save()
        defer {
            context.delete(card)
            try? context.save()
        }

        let remote = CardSyncRecord(
            id: card.id,
            storeName: "Санта",
            barcodeKind: BarcodeKind.ean13.rawValue,
            barcodePayload: "4600721000011",
            sortOrder: 4,
            note: "вторая касса",
            colorHex: "30D158",
            symbolName: "basket.fill",
            updatedAt: Date().addingTimeInterval(60),
            places: [CardSyncPlace(name: "У дома", address: "Ленина, 1", latitude: 52.097621, longitude: 23.734455)]
        )
        remote.apply(to: card, in: context)

        #expect(card.logoImageData == logo)
        #expect(card.locations.contains { !$0.isUserDefined && $0.name == "OSM-СКЛАД-НЕ-СИНХ" })
        #expect(card.userPlaces.map(\.name) == ["У дома"])
        #expect(card.note == "вторая касса")
        #expect(card.position == 4)

        let payload = CardSyncRecord(card)
        let text = String(decoding: try JSONEncoder().encode(payload.document), as: UTF8.self)
        #expect(payload.places.map(\.name) == ["У дома"])
        #expect(!text.contains("OSM-СКЛАД-НЕ-СИНХ"))
        #expect(!text.contains("logo-bytes-DEADBEEF"))
    }

    @Test func emptyFieldsAndMismatchedPasswordsStayLocal() {
        #expect(AccountAuthForm.rejection(mode: .signIn, email: "  ", password: "secret", confirmation: "") == "Введите почту.")
        #expect(AccountAuthForm.rejection(mode: .signIn, email: "a@b.c", password: "", confirmation: "") == "Введите пароль.")
        #expect(AccountAuthForm.rejection(mode: .createAccount, email: "a@b.c", password: "secret", confirmation: "") == "Повторите пароль.")
        #expect(AccountAuthForm.rejection(mode: .createAccount, email: "a@b.c", password: "secret", confirmation: "other") == "Пароли не совпадают.")
        #expect(AccountAuthForm.rejection(mode: .signIn, email: "a@b.c", password: "secret", confirmation: "other") == nil)
        #expect(AccountAuthForm.rejection(mode: .createAccount, email: "a@b.c", password: "secret", confirmation: "secret") == nil)
    }

    @Test func googleMarkKeepsBrandColors() {
        #expect([GoogleMark.blue, GoogleMark.red, GoogleMark.yellow, GoogleMark.green] == [
            "4285F4", "EA4335", "FBBC05", "34A853",
        ])
        let box = CGRect(x: 0, y: 0, width: 18, height: 18)
        var union = CGRect.null
        for source in [GoogleMark.redPath, GoogleMark.bluePath, GoogleMark.yellowPath, GoogleMark.greenPath] {
            let bounds = GoogleLogoPath.shape(source, in: box).boundingRect
            #expect(bounds.width > 1)
            #expect(bounds.height > 1)
            #expect(bounds.minX >= -0.5)
            #expect(bounds.minY >= -0.5)
            #expect(bounds.maxX <= 18.5)
            #expect(bounds.maxY <= 18.5)
            union = union.union(bounds)
        }
        #expect(union.width > 16)
        #expect(union.height > 16)
    }

    @Test func googleSignInNeedsRealClientIDs() {
        #expect(GoogleSignInConfig.read(from: [:]) == nil)
        #expect(GoogleSignInConfig.read(from: ["CLIENT_ID": ""]) == nil)
        #expect(GoogleSignInConfig.read(from: ["CLIENT_ID": "YOUR_CLIENT_ID", "REVERSED_CLIENT_ID": "com.googleusercontent.apps.1"]) == nil)
        #expect(GoogleSignInConfig.read(from: ["CLIENT_ID": "123.apps.googleusercontent.com"]) == nil)
        #expect(GoogleSignInConfig.read(from: [
            "CLIENT_ID": "123.apps.googleusercontent.com",
            "REVERSED_CLIENT_ID": "YOUR_REVERSED_CLIENT_ID",
        ]) == nil)
        let ids = GoogleSignInConfig.read(from: [
            "CLIENT_ID": " 123.apps.googleusercontent.com ",
            "REVERSED_CLIENT_ID": "com.googleusercontent.apps.123",
        ])
        #expect(ids == GoogleClientIDs(
            clientID: "123.apps.googleusercontent.com",
            reversedClientID: "com.googleusercontent.apps.123"
        ))
    }

    @Test func authErrorsUseTheFirebaseCases() {
        #expect(CardSyncService.authMessage(authError(17009)) == "Неверный пароль.")
        #expect(CardSyncService.authMessage(authError(17004)) == "Неверный пароль.")
        #expect(CardSyncService.authMessage(authError(17011)) == "Аккаунт с этой почтой не найден.")
        #expect(CardSyncService.authMessage(authError(17007)) == "Этот адрес уже зарегистрирован. Войдите.")
        #expect(CardSyncService.authMessage(authError(17026)) == "Пароль должен быть не короче 6 символов.")
        #expect(CardSyncService.authMessage(authError(17020)) == "Нет сети. Попробуйте ещё раз, когда она появится.")
    }

    private func authError(_ code: Int) -> NSError {
        NSError(domain: "FIRAuthErrorDomain", code: code)
    }

    @Test func newerTimestampWins() {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(2)
        #expect(CardSyncMerge.winner(local: older, remote: newer) == .remote)
        #expect(CardSyncMerge.winner(local: newer, remote: older) == .local)
        #expect(CardSyncMerge.winner(local: older, remote: older) == .local)
        #expect(CardSyncMerge.winner(local: older, remote: older.addingTimeInterval(0.0001)) == .local)
    }
}
