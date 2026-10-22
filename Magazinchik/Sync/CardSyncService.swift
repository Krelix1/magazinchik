import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftData

/// Mirrors loyalty cards and «Мои места» to `users/{uid}/cards/{cardId}`.
/// SwiftData stays what the screen reads. A missing Firebase plist leaves this idle.
@MainActor
@Observable
final class CardSyncService {
    enum Phase: Equatable {
        case unavailable
        case signedOut
        case signingIn
        case syncing
        case synced
        case waitingForNetwork
        case failed
    }

    private(set) var phase: Phase = .unavailable
    private(set) var accountEmail: String?
    private(set) var lastError: String?

    private var context: ModelContext?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var registration: ListenerRegistration?
    private var uid: String?
    private var didReconcile = false
    private var storeFetchAttempted: Set<UUID> = []

    var statusTitle: String {
        switch phase {
        case .unavailable: "Выключена"
        case .signedOut: "Нет входа"
        case .signingIn: "Вход…"
        case .syncing: "Синхронизация…"
        case .synced: "Синхронизировано"
        case .waitingForNetwork: "Ждёт сеть"
        case .failed: "Не отправилось"
        }
    }

    init() {
        FirebaseGate.configureIfPresent()
        phase = FirebaseGate.isConfigured ? .signedOut : .unavailable
    }

    func bind(_ context: ModelContext) {
        self.context = context
        guard FirebaseGate.isConfigured else {
            phase = .unavailable
            return
        }
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { _, user in
            let signedIn = user.map { (uid: $0.uid, email: $0.email) }
            Task { @MainActor in
                self.handleAuth(signedIn)
            }
        }
    }

    func signIn(email: String, password: String) async {
        await authenticate(email: email, password: password, create: false)
    }

    func createAccount(email: String, password: String) async {
        await authenticate(email: email, password: password, create: true)
    }

    var googleSignInAvailable: Bool {
        FirebaseGate.isConfigured && GoogleSignInConfig.current != nil
    }

    func signInWithGoogle() async {
        guard FirebaseGate.isConfigured, let clientID = GoogleSignInConfig.current?.clientID else {
            phase = .unavailable
            return
        }
        phase = .signingIn
        lastError = nil
        do {
            let credential = try await GoogleSignInBridge.credential(clientID: clientID)
            try await Auth.auth().signIn(with: credential)
        } catch {
            if GoogleSignInBridge.isCancellation(error) {
                lastError = nil
                phase = .signedOut
                return
            }
            lastError = Self.authMessage(error)
            phase = .failed
        }
    }

    func signOut() {
        guard FirebaseGate.isConfigured else { return }
        GoogleSignInBridge.signOut()
        do {
            try Auth.auth().signOut()
            lastError = nil
        } catch {
            lastError = "Не удалось выйти."
            phase = .failed
        }
    }

    func upload(_ card: LoyaltyCard) {
        upload([card])
    }

    func upload(_ cards: [LoyaltyCard]) {
        guard FirebaseGate.isConfigured, let uid, !cards.isEmpty else { return }
        let collection = Self.cards(uid)
        for card in cards {
            let record = CardSyncRecord(card)
            collection.document(card.id.uuidString).setData(record.firestoreData()) { error in
                guard let error else { return }
                Task { @MainActor in
                    self.noteWrite(error)
                }
            }
        }
    }

    func delete(_ id: UUID) {
        guard FirebaseGate.isConfigured, let uid else { return }
        Self.cards(uid).document(id.uuidString).delete { error in
            guard let error else { return }
            Task { @MainActor in
                self.noteWrite(error)
            }
        }
    }

    /// Downloads city stores for cards that arrived from another phone. The catalog is not in the sync payload.
    func fillStoresForUncachedCards() {
        guard let context, FirebaseGate.isConfigured else { return }
        let cards = (try? context.fetch(FetchDescriptor<LoyaltyCard>())) ?? []
        for card in cards {
            scheduleStoreFill(card, in: context)
        }
    }

    private func authenticate(email: String, password: String, create: Bool) async {
        guard FirebaseGate.isConfigured else {
            phase = .unavailable
            return
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .signingIn
        lastError = nil
        do {
            if create {
                try await Auth.auth().createUser(withEmail: trimmed, password: password)
            } else {
                try await Auth.auth().signIn(withEmail: trimmed, password: password)
            }
        } catch {
            lastError = Self.authMessage(error)
            phase = .failed
        }
    }

    private func handleAuth(_ user: (uid: String, email: String?)?) {
        guard let user else {
            stopListening()
            accountEmail = nil
            uid = nil
            phase = .signedOut
            return
        }
        accountEmail = user.email
        uid = user.uid
        guard registration == nil || user.uid != listeningUID else { return }
        listen(uid: user.uid)
    }

    private var listeningUID: String?

    private func listen(uid: String) {
        stopListening()
        self.uid = uid
        listeningUID = uid
        didReconcile = false
        phase = .syncing
        registration = Self.cards(uid).addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            let batch = snapshot.map(CardSyncSnapshotReader.batch)
            Task { @MainActor in
                if let batch {
                    self.ingest(batch)
                } else if let error {
                    self.noteWrite(error)
                }
            }
        }
    }

    private func stopListening() {
        registration?.remove()
        registration = nil
        listeningUID = nil
        didReconcile = false
    }

    private func ingest(_ batch: CardSyncBatch) {
        guard let context else { return }
        if !didReconcile {
            removeUntouchedSamples(ifRemoteHasCards: !batch.remoteIDs.isEmpty, in: context)
        }

        for event in batch.events {
            switch event.kind {
            case .upsert:
                guard let record = event.record else { continue }
                merge(record, in: context)
            case .removed:
                deleteLocal(event.id, in: context)
            }
        }

        if !didReconcile {
            didReconcile = true
            uploadMissing(remoteIDs: Set(batch.remoteIDs), in: context)
            fillStoresForUncachedCards()
        }
        try? context.save()
        if batch.hasPendingWrites {
            phase = .waitingForNetwork
        } else if batch.isFromCache {
            phase = .syncing
        } else {
            phase = .synced
            lastError = nil
        }
    }

    private func merge(_ remote: CardSyncRecord, in context: ModelContext) {
        if let local = card(remote.id, in: context) {
            switch CardSyncMerge.winner(local: local.updatedAt, remote: remote.updatedAt) {
            case .remote:
                let renamed = local.storeName != remote.storeName
                remote.apply(to: local, in: context)
                if renamed { storeFetchAttempted.remove(local.id) }
                scheduleStoreFill(local, in: context)
            case .local:
                if local.updatedAt.timeIntervalSince(remote.updatedAt) > CardSyncMerge.tie {
                    upload(local)
                }
            }
        } else {
            let created = remote.makeCard(in: context)
            scheduleStoreFill(created, in: context)
        }
    }

    private func uploadMissing(remoteIDs: Set<UUID>, in context: ModelContext) {
        let cards = (try? context.fetch(FetchDescriptor<LoyaltyCard>())) ?? []
        let missing = cards.filter { card in
            !remoteIDs.contains(card.id) && !DemoWallet.isUntouchedSample(card)
        }
        upload(missing)
    }

    private func removeUntouchedSamples(ifRemoteHasCards hasRemote: Bool, in context: ModelContext) {
        guard hasRemote else { return }
        let cards = (try? context.fetch(FetchDescriptor<LoyaltyCard>())) ?? []
        for card in cards where DemoWallet.isUntouchedSample(card) {
            context.delete(card)
        }
    }

    private func deleteLocal(_ id: UUID, in context: ModelContext) {
        guard let card = card(id, in: context) else { return }
        context.delete(card)
    }

    private func card(_ id: UUID, in context: ModelContext) -> LoyaltyCard? {
        let cards = (try? context.fetch(FetchDescriptor<LoyaltyCard>())) ?? []
        return cards.first { $0.id == id }
    }

    private func scheduleStoreFill(_ card: LoyaltyCard, in context: ModelContext) {
        guard card.findsStoresAutomatically else { return }
        guard card.storesSearchedAt == nil, !card.hasAutomaticPlaces else { return }
        let cities = (try? context.fetch(FetchDescriptor<CityRecord>())) ?? []
        guard cities.contains(where: \.isActive) else { return }
        guard storeFetchAttempted.insert(card.id).inserted else { return }
        let cardID = card.id
        Task { @MainActor in
            await BrandStoreCache.ensureStores(for: cardID, in: context)
        }
    }

    private func noteWrite(_ error: Error) {
        let ns = error as NSError
        guard ns.domain == FirestoreErrorDomain else {
            lastError = "Не удалось отправить изменения."
            phase = .failed
            return
        }
        guard let code = FirestoreErrorCode.Code(rawValue: ns.code) else {
            lastError = "Не удалось отправить изменения."
            phase = .failed
            return
        }
        switch code {
        case .cancelled, .unavailable, .deadlineExceeded:
            if phase != .signedOut, phase != .unavailable {
                phase = .waitingForNetwork
            }
        case .permissionDenied, .unauthenticated:
            lastError = "Нет доступа к синхронизации."
            phase = .failed
        default:
            lastError = "Не удалось отправить изменения."
            phase = .failed
        }
    }

    private static func cards(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("cards")
    }

    static func authMessage(_ error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: ns.code) else {
            return "Не удалось войти. Попробуйте ещё раз."
        }
        switch code {
        case .invalidEmail:
            return "Проверьте адрес почты."
        case .wrongPassword, .invalidCredential:
            return "Неверный пароль."
        case .userNotFound:
            return "Аккаунт с этой почтой не найден."
        case .emailAlreadyInUse:
            return "Этот адрес уже зарегистрирован. Войдите."
        case .weakPassword:
            return "Пароль должен быть не короче 6 символов."
        case .networkError:
            return "Нет сети. Попробуйте ещё раз, когда она появится."
        case .operationNotAllowed:
            return "В Firebase не включён этот способ входа."
        case .tooManyRequests:
            return "Слишком много попыток. Подождите немного."
        default:
            return "Не удалось войти. Попробуйте ещё раз."
        }
    }
}

private struct CardSyncEvent: Sendable {
    enum Kind: Sendable {
        case upsert
        case removed
    }

    var kind: Kind
    var id: UUID
    var record: CardSyncRecord?
}

private struct CardSyncBatch: Sendable {
    var events: [CardSyncEvent]
    var remoteIDs: [UUID]
    var hasPendingWrites: Bool
    var isFromCache: Bool
}

private enum CardSyncSnapshotReader {
    static func batch(from snapshot: QuerySnapshot) -> CardSyncBatch {
        var events: [CardSyncEvent] = []
        events.reserveCapacity(snapshot.documentChanges.count)
        for change in snapshot.documentChanges {
            guard let id = UUID(uuidString: change.document.documentID) else { continue }
            switch change.type {
            case .removed:
                events.append(CardSyncEvent(kind: .removed, id: id, record: nil))
            case .added, .modified:
                let data = change.document.data()
                guard let record = CardSyncDecoding.record(id: id, data: data) else { continue }
                events.append(CardSyncEvent(kind: .upsert, id: id, record: record))
            default:
                continue
            }
        }
        let remoteIDs = snapshot.documents.compactMap { UUID(uuidString: $0.documentID) }
        return CardSyncBatch(
            events: events,
            remoteIDs: remoteIDs,
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
            isFromCache: snapshot.metadata.isFromCache
        )
    }
}

private enum CardSyncDecoding {
    static func record(id: UUID, data: [String: Any]) -> CardSyncRecord? {
        guard
            let storeName = data["storeName"] as? String,
            let barcodeKind = data["barcodeKind"] as? String,
            let barcodePayload = data["barcodePayload"] as? String,
            let sortOrder = (data["sortOrder"] as? NSNumber)?.intValue,
            let note = data["note"] as? String,
            let colorHex = data["colorHex"] as? String,
            let symbolName = data["symbolName"] as? String,
            let updatedAt = date(data["updatedAt"])
        else { return nil }
        let places = (data["places"] as? [[String: Any]])?.compactMap(CardSyncPlace.init(firestore:)) ?? []
        return CardSyncRecord(
            id: id,
            storeName: storeName,
            barcodeKind: barcodeKind,
            barcodePayload: barcodePayload,
            sortOrder: sortOrder,
            note: note,
            colorHex: colorHex,
            symbolName: symbolName,
            updatedAt: updatedAt,
            places: places
        )
    }

    static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }
}

private extension CardSyncPlace {
    init?(firestore data: [String: Any]) {
        guard
            let name = data["name"] as? String,
            let address = data["address"] as? String,
            let latitude = (data["latitude"] as? NSNumber)?.doubleValue,
            let longitude = (data["longitude"] as? NSNumber)?.doubleValue
        else { return nil }
        self.init(name: name, address: address, latitude: latitude, longitude: longitude)
    }
}

extension CardSyncRecord {
    func firestoreData() -> [String: Any] {
        [
            "storeName": storeName,
            "barcodeKind": barcodeKind,
            "barcodePayload": barcodePayload,
            "sortOrder": sortOrder,
            "note": note,
            "colorHex": colorHex,
            "symbolName": symbolName,
            "updatedAt": Timestamp(date: updatedAt),
            "places": places.map {
                [
                    "name": $0.name,
                    "address": $0.address,
                    "latitude": $0.latitude,
                    "longitude": $0.longitude,
                ]
            },
        ]
    }
}
