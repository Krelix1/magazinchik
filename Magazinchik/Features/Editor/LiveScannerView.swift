import AVFoundation
import SwiftUI
import VisionKit

/// Full-screen live camera that closes itself on the first barcode or QR it reads.
struct LiveScannerScreen: View {
    let onFound: (String, BarcodeKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed: Bool?

    static var isSupported: Bool { DataScannerViewController.isSupported }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch cameraAllowed {
            case .some(true) where DataScannerViewController.isAvailable:
                DataScannerRepresentable { payload, kind in
                    onFound(payload, kind)
                    dismiss()
                }
                .ignoresSafeArea()
            case .some:
                ContentUnavailableView {
                    Label("Камера недоступна", systemImage: "camera.fill")
                } description: {
                    Text("Разрешите доступ к камере в Настройках или выберите фото карты из галереи.")
                } actions: {
                    Button("Открыть Настройки") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.glassProminent)
                }
                .foregroundStyle(.white)
            case .none:
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityLabel("Закрыть")
            .padding()
        }
        .overlay(alignment: .bottom) {
            if cameraAllowed == true {
                Text("Наведите камеру на штрихкод или QR-код")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 32)
            }
        }
        .task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: cameraAllowed = true
            case .notDetermined: cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
            default: cameraAllowed = false
            }
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onFound: (String, BarcodeKind) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFound: onFound)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String, BarcodeKind) -> Void
        private var didFind = false

        init(onFound: @escaping (String, BarcodeKind) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didFind else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, !payload.isEmpty {
                    didFind = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onFound(payload, BarcodeKind(symbology: barcode.observation.symbology, payload: payload))
                    return
                }
            }
        }
    }
}
