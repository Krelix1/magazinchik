import Foundation
import SwiftData

/// Editable copy of a card, so Cancel leaves the stored card untouched.
struct CardDraft {
    var storeName = ""
    var number = ""
    var kind: BarcodeKind = .ean13
    var colorHex = Theme.defaultCardColor
    var symbolName = Theme.symbols[0]
    var logoData: Data?
    var note = ""
    var brandQuery = ""
    var findsStoresAutomatically = true
    /// Stores the person attached by hand; automatically found ones are managed by `StoreLocator`.
    var places: [PlaceDraft] = []

    init() {}

    init(_ card: LoyaltyCard?) {
        guard let card else { return }
        storeName = card.storeName
        number = card.number
        kind = card.barcodeKind
        colorHex = card.colorHex
        symbolName = card.symbolName
        logoData = card.logoImageData
        note = card.note
        brandQuery = card.brandQuery
        findsStoresAutomatically = card.findsStoresAutomatically
        places = card.locations.filter(\.isUserDefined).map { PlaceDraft($0) }
    }

    var trimmedName: String { storeName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedNumber: String { number.trimmingCharacters(in: .whitespacesAndNewlines) }

    var searchQuery: String { trimmedName }

    var numberProblem: String? { kind.problem(with: trimmedNumber) }

    var canSave: Bool { !trimmedName.isEmpty && numberProblem == nil }

    func apply(to card: LoyaltyCard, in context: ModelContext) {
        let searchChanged = card.searchQuery != searchQuery || card.findsStoresAutomatically != findsStoresAutomatically

        card.storeName = trimmedName
        card.number = trimmedNumber
        card.barcodeKind = kind
        card.colorHex = colorHex
        card.symbolName = symbolName
        card.logoImageData = logoData
        card.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        card.brandQuery = brandQuery.trimmingCharacters(in: .whitespaces)
        card.findsStoresAutomatically = findsStoresAutomatically

        let removing = card.locations.filter { $0.isUserDefined || searchChanged }
        for location in removing {
            context.delete(location)
        }
        for place in places {
            let location = place.makeLocation(isUserDefined: true)
            location.card = card
            context.insert(location)
        }

        if searchChanged { card.invalidateStoreSearch() }
        card.contentRevision += 1
        card.updatedAt = Date()
    }
}
