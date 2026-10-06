import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Black-on-white code for the checkout scanner. Put it on a white plate; it carries no background of its own.
struct BarcodeView: View {
    let kind: BarcodeKind
    let payload: String

    var body: some View {
        switch kind {
        case .none:
            EmptyView()
        case .ean13, .ean8:
            if let modules = EANEncoder.modules(for: payload) {
                LinearBars(modules: modules)
                    .accessibilityLabel("Штрихкод \(kind.title)")
            } else {
                invalid
            }
        case .code128, .qr, .pdf417, .aztec:
            if let image = BarcodeRenderer.image(kind: kind, payload: payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .accessibilityLabel(kind == .qr ? "QR-код" : "Штрихкод \(kind.title)")
            } else {
                invalid
            }
        }
    }

    private var invalid: some View {
        Label("Не получается построить код", systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.black.opacity(0.6))
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}

/// Draws EAN modules with pixel-aligned runs so bars stay crisp at any width.
private struct LinearBars: View {
    let modules: [Bool]

    var body: some View {
        Canvas { context, size in
            let moduleWidth = size.width / CGFloat(modules.count)
            var index = 0
            while index < modules.count {
                guard modules[index] else { index += 1; continue }
                let start = index
                while index < modules.count, modules[index] { index += 1 }
                let rect = CGRect(
                    x: CGFloat(start) * moduleWidth,
                    y: 0,
                    width: CGFloat(index - start) * moduleWidth,
                    height: size.height
                )
                context.fill(Path(rect), with: .color(.black))
            }
        }
    }
}

@MainActor
enum BarcodeRenderer {
    private static let context = CIContext()
    private static let cache = NSCache<NSString, UIImage>()

    static func image(kind: BarcodeKind, payload: String) -> UIImage? {
        let key = "\(kind.rawValue)|\(payload)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let output = ciImage(kind: kind, payload: payload) else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }

    private static func ciImage(kind: BarcodeKind, payload: String) -> CIImage? {
        switch kind {
        case .qr:
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(payload.utf8)
            filter.correctionLevel = "M"
            return filter.outputImage
        case .code128:
            guard let data = payload.data(using: .ascii) else { return nil }
            let filter = CIFilter.code128BarcodeGenerator()
            filter.message = data
            filter.quietSpace = 0
            return filter.outputImage
        case .pdf417:
            let filter = CIFilter.pdf417BarcodeGenerator()
            filter.message = Data(payload.utf8)
            return filter.outputImage
        case .aztec:
            let filter = CIFilter.aztecCodeGenerator()
            filter.message = Data(payload.utf8)
            return filter.outputImage
        case .ean13, .ean8, .none:
            return nil
        }
    }
}

/// White plate with the code and the human-readable number under it.
struct BarcodePlate: View {
    let kind: BarcodeKind
    let number: String
    var codeHeight: CGFloat = 110

    var body: some View {
        VStack(spacing: 10) {
            if kind != .none {
                BarcodeView(kind: kind, payload: number)
                    .frame(height: kind.isTwoDimensional ? codeHeight * 1.8 : codeHeight)
                    .frame(maxWidth: kind.isTwoDimensional ? codeHeight * 1.8 : .infinity)
            }
            Text(CardText.grouped(number))
                .font(kind == .none ? .system(.title, design: .monospaced, weight: .semibold) : .system(.callout, design: .monospaced))
                .foregroundStyle(.black)
                .textSelection(.enabled)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .background(.white, in: .rect(cornerRadius: 20, style: .continuous))
    }
}
