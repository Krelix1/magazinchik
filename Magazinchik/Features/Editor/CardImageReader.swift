import ImageIO
import UIKit
import Vision

/// Reads a card photo on device: barcode or QR first, OCR of the printed number as a fallback.
enum CardImageReader {
    struct Result: Sendable {
        var payload: String
        var kind: BarcodeKind
        var fromBarcode: Bool
    }

    static func read(_ image: UIImage) async -> Result? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            readSync(cgImage, orientation: orientation)
        }.value
    }

    private static func readSync(_ image: CGImage, orientation: CGImagePropertyOrientation) -> Result? {
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)

        let barcodes = VNDetectBarcodesRequest()
        try? handler.perform([barcodes])
        let best = (barcodes.results ?? [])
            .filter { !($0.payloadStringValue ?? "").isEmpty }
            .max { $0.confidence < $1.confidence }
        if let best, let payload = best.payloadStringValue {
            return Result(payload: payload, kind: BarcodeKind(symbology: best.symbology, payload: payload), fromBarcode: true)
        }

        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false
        text.recognitionLanguages = ["ru-RU", "en-US"]
        try? handler.perform([text])
        let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard let number = CardText.bestNumber(in: lines) else { return nil }
        return Result(payload: number, kind: .guess(for: number), fromBarcode: false)
    }
}

extension BarcodeKind {
    /// Maps what Vision saw to a symbology we can render back; falls back to a guess when the payload doesn't fit.
    init(symbology: VNBarcodeSymbology, payload: String) {
        let mapped: BarcodeKind
        switch symbology {
        case .ean13: mapped = .ean13
        case .ean8: mapped = .ean8
        case .qr, .microQR, .dataMatrix: mapped = .qr
        case .pdf417, .microPDF417: mapped = .pdf417
        case .aztec: mapped = .aztec
        default: mapped = .code128
        }
        self = mapped.problem(with: payload) == nil ? mapped : .guess(for: payload)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
