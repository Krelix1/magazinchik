import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// All cards in the person's own order, 1–4 per row. Long-press and drag to reorder.
struct WalletView: View {
    let cards: [LoyaltyCard]
    let snapshot: NearbySnapshot

    @Environment(\.modelContext) private var context
    @AppStorage("wallet.columns") private var columns = GridDensity.two.rawValue
    @State private var dragging: LoyaltyCard?
    @State private var isAdding = false
    @State private var editing: LoyaltyCard?
    @State private var pendingDeletion: LoyaltyCard?

    private var density: GridDensity { GridDensity(rawValue: columns) ?? .two }

    private var spacing: CGFloat {
        switch density {
        case .one, .two: 12
        case .three: 10
        case .four: 8
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if cards.isEmpty {
                        EmptyWalletView { isAdding = true }
                    } else {
                        HStack {
                            Text(CardText.cardCount(cards.count))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            DensityPicker(columns: $columns)
                        }

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: density.columns),
                            spacing: spacing
                        ) {
                            ForEach(cards) { card in
                                tile(for: card)
                            }
                        }

                        Text("Удерживайте карту и перетащите, чтобы поменять порядок.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, Theme.padding)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .animation(Theme.spring, value: columns)
            }
            .screenBackground()
            .navigationTitle("Все карты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AddCardButton { isAdding = true }
                }
                .glassToolbarItem()
            }
            .navigationDestination(for: LoyaltyCard.self) { card in
                CardDetailView(card: card, distance: snapshot.distance(for: card.id))
            }
            .sheet(isPresented: $isAdding) {
                CardEditorView(card: nil)
            }
            .sheet(item: $editing) { card in
                CardEditorView(card: card)
            }
            .confirmationDialog(
                "Удалить карту «\(pendingDeletion?.storeName ?? "")»?",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    if let card = pendingDeletion {
                        context.delete(card)
                        try? context.save()
                    }
                    pendingDeletion = nil
                }
            }
        }
    }

    private func tile(for card: LoyaltyCard) -> some View {
        NavigationLink(value: card) {
            CardTile(
                card: card,
                density: density,
                isSuggested: card.id == snapshot.suggestedID,
                distance: snapshot.distance(for: card.id)
            )
        }
        .buttonStyle(.plain)
        .onDrag {
            dragging = card
            return NSItemProvider(object: card.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: ReorderDropDelegate(target: card, cards: cards, dragging: $dragging) {
            try? context.save()
        })
        .contextMenu {
            Button("Изменить", systemImage: "pencil") { editing = card }
            Button("В начало", systemImage: "arrow.up.to.line") {
                reorder(CardOrdering.moveToFront(card.id, in: cards.map(\.id)))
            }
            Button("В конец", systemImage: "arrow.down.to.line") {
                reorder(CardOrdering.moveToBack(card.id, in: cards.map(\.id)))
            }
            Divider()
            Button("Удалить", systemImage: "trash", role: .destructive) { pendingDeletion = card }
        }
    }

    private func reorder(_ order: [UUID]) {
        withAnimation(Theme.spring) {
            WalletOrder.apply(order, to: cards)
        }
        try? context.save()
    }
}

enum WalletOrder {
    /// Writes contiguous positions so every card keeps its own persistent slot.
    static func apply(_ order: [UUID], to cards: [LoyaltyCard]) {
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        for card in cards {
            if let position = index[card.id], card.position != position {
                card.position = position
            }
        }
    }
}

/// Live reordering: the dragged card takes the slot of whichever card it hovers.
@MainActor
private struct ReorderDropDelegate: DropDelegate {
    let target: LoyaltyCard
    let cards: [LoyaltyCard]
    @Binding var dragging: LoyaltyCard?
    let onCommit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != target.id else { return }
        let order = CardOrdering.move(dragging.id, onto: target.id, in: cards.map(\.id))
        withAnimation(Theme.bouncySpring) {
            WalletOrder.apply(order, to: cards)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        onCommit()
        return true
    }
}

/// 1 / 2 / 3 / 4 columns, as a row of glass buttons.
private struct DensityPicker: View {
    @Binding var columns: Int

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(GridDensity.allCases) { option in
                    let isSelected = option.rawValue == columns
                    Button {
                        columns = option.rawValue
                    } label: {
                        Image(systemName: option.symbolName)
                            .font(.footnote.weight(.semibold))
                            .frame(width: 20, height: 20)
                    }
                    .glassButtonStyle(prominent: isSelected)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(option.accessibilityName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: columns)
    }
}
