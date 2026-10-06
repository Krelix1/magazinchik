import PhotosUI
import SwiftData
import SwiftUI

/// Add or edit a card. Filling from a photo and typing by hand live on one screen: fewer steps, same result.
struct CardEditorView: View {
    let card: LoyaltyCard?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location

    @State private var draft: CardDraft
    @State private var importStatus: ImportStatus = .idle
    @State private var photoItem: PhotosPickerItem?
    @State private var logoItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var isTakingPhoto = false
    @State private var isSearchingPlace = false

    init(card: LoyaltyCard?) {
        self.card = card
        _draft = State(initialValue: CardDraft(card))
    }

    var body: some View {
        NavigationStack {
            Form {
                preview
                importSection
                storeSection
                codeSection
                appearanceSection
                Section("Заметка") {
                    TextField("Например, скидка 10% по средам", text: $draft.note, axis: .vertical)
                        .lineLimit(1...4)
                }
                placesSection
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(card == nil ? "Новая карта" : "Изменить карту")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Отменить")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .disabled(!draft.canSave)
                        .accessibilityLabel("Сохранить")
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await read(image)
                    } else {
                        importStatus = .failed("Не удалось открыть фото")
                    }
                    photoItem = nil
                }
            }
            .onChange(of: logoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        draft.logoData = Self.logoData(from: image)
                    }
                    logoItem = nil
                }
            }
            .fullScreenCover(isPresented: $isScanning) {
                LiveScannerScreen { payload, kind in
                    draft.number = payload
                    draft.kind = kind
                    importStatus = .found("Считали \(kind.title)")
                }
            }
            .fullScreenCover(isPresented: $isTakingPhoto) {
                CameraPicker { image in
                    Task { await read(image) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isSearchingPlace) {
                PlaceSearchView(initialQuery: draft.searchQuery) { place in
                    draft.places.append(place)
                }
            }
            .sensoryFeedback(trigger: importStatus) { _, new in
                switch new {
                case .found: .success
                case .failed: .warning
                default: nil
                }
            }
        }
    }

    // MARK: Sections

    private var preview: some View {
        Section {
            VStack(spacing: 14) {
                CardIcon(symbolName: draft.symbolName, colorHex: draft.colorHex, logoData: draft.logoData, size: 56)
                Text(draft.trimmedName.isEmpty ? "Новая карта" : draft.trimmedName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(draft.trimmedName.isEmpty ? .secondary : .primary)
                if draft.kind != .none, draft.numberProblem == nil {
                    BarcodePlate(kind: draft.kind, number: draft.trimmedNumber, codeHeight: 64)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .animation(Theme.spring, value: draft.numberProblem == nil)
        }
        .listRowBackground(Color.clear)
    }

    private var importSection: some View {
        Section {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if LiveScannerScreen.isSupported {
                        Button { isScanning = true } label: {
                            GlassTileLabel(title: "Сканер", systemImage: "barcode.viewfinder")
                        }
                    }
                    if CameraPicker.isAvailable {
                        Button { isTakingPhoto = true } label: {
                            GlassTileLabel(title: "Снимок", systemImage: "camera")
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        GlassTileLabel(title: "Из фото", systemImage: "photo.on.rectangle")
                    }
                }
                .buttonStyle(.glass)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
            Text("Заполнить с фото")
        } footer: {
            switch importStatus {
            case .idle:
                Text("Штрихкод или QR считается сам. Если кода нет, распознаем номер с фото.")
            case .reading:
                Label("Читаем фото…", systemImage: "hourglass")
            case .found(let message):
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.positive)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            }
        }
    }

    private var storeSection: some View {
        Section("Магазин") {
            TextField("Название, например «Пятёрочка»", text: $draft.storeName)
                .textInputAutocapitalization(.words)
        }
    }

    private var codeSection: some View {
        Section {
            TextField("Номер карты", text: $draft.number)
                .font(.body.monospaced())
                .keyboardType(draft.kind.isNumericOnly ? .numberPad : .asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker("Тип кода", selection: $draft.kind) {
                ForEach(BarcodeKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
        } header: {
            Text("Карта")
        } footer: {
            if !draft.number.isEmpty, let problem = draft.numberProblem {
                Text(problem).foregroundStyle(.orange)
            }
        }
    }

    private var appearanceSection: some View {
        Section("Цвет и значок") {
            GlassEffectContainer(spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                    ForEach(Theme.palette, id: \.self) { hex in
                        let isSelected = draft.colorHex == hex
                        Button {
                            draft.colorHex = hex
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.bold))
                                .opacity(isSelected ? 1 : 0)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(Color(hex: hex))
                        .accessibilityLabel(Theme.colorName(hex))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 4)

            GlassEffectContainer(spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                    ForEach(Theme.symbols, id: \.self) { symbol in
                        let isSelected = draft.symbolName == symbol && draft.logoData == nil
                        Button {
                            draft.symbolName = symbol
                            draft.logoData = nil
                        } label: {
                            Image(systemName: symbol)
                                .font(.body)
                                .frame(width: 22, height: 22)
                        }
                        .glassButtonStyle(prominent: isSelected)
                        .buttonBorderShape(.circle)
                        .tint(Color(hex: draft.colorHex))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 4)

            HStack {
                PhotosPicker(selection: $logoItem, matching: .images) {
                    Label(draft.logoData == nil ? "Логотип из фото" : "Другой логотип", systemImage: "photo")
                }
                .buttonStyle(.glass)
                if draft.logoData != nil {
                    Spacer()
                    Button("Убрать", role: .destructive) { draft.logoData = nil }
                        .buttonStyle(.glass)
                }
            }
        }
    }

    private var placesSection: some View {
        Section {
            Toggle("Находить магазины сети рядом", isOn: $draft.findsStoresAutomatically)
            if draft.findsStoresAutomatically {
                TextField(
                    "Как искать на карте",
                    text: $draft.brandQuery,
                    prompt: Text(draft.trimmedName.isEmpty ? "Название сети" : draft.trimmedName)
                )
            }
            ForEach(draft.places) { place in
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                    if !place.address.isEmpty {
                        Text(place.address).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { draft.places.remove(atOffsets: $0) }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: addCurrentLocation) {
                        Label("Я сейчас здесь", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(location.location == nil)
                    Button { isSearchingPlace = true } label: {
                        Label("Найти адрес", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glass)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
            Text("Где пользуюсь")
        } footer: {
            Text("Когда вы окажетесь у одного из этих магазинов, карта сама встанет первой. Магазины сети ищутся на Картах Apple по названию.")
        }
    }

    // MARK: Actions

    private func read(_ image: UIImage) async {
        importStatus = .reading
        guard let result = await CardImageReader.read(image) else {
            importStatus = .failed("Не нашли ни кода, ни номера. Введите номер вручную.")
            return
        }
        draft.number = result.payload
        draft.kind = result.kind
        importStatus = .found(result.fromBarcode ? "Считали \(result.kind.title)" : "Номер распознан по тексту — проверьте его")
    }

    private func addCurrentLocation() {
        guard let coordinate = location.location?.coordinate else { return }
        let name = draft.trimmedName.isEmpty ? "Мой магазин" : draft.trimmedName
        draft.places.append(PlaceDraft(name: name, address: "Отмечено на месте", latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    private func save() {
        let target: LoyaltyCard
        if let card {
            target = card
        } else {
            let lastPosition = (try? context.fetch(FetchDescriptor<LoyaltyCard>()))?.map(\.position).max() ?? -1
            target = LoyaltyCard(storeName: draft.trimmedName, number: draft.trimmedNumber, barcodeKind: draft.kind, position: lastPosition + 1)
            context.insert(target)
        }
        draft.apply(to: target, in: context)
        try? context.save()
        dismiss()
    }

    private static func logoData(from image: UIImage) -> Data? {
        let side: CGFloat = 256
        let scale = side / max(image.size.width, image.size.height, 1)
        let size = CGSize(width: image.size.width * min(scale, 1), height: image.size.height * min(scale, 1))
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

private enum ImportStatus: Equatable {
    case idle
    case reading
    case found(String)
    case failed(String)
}
