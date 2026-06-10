import AppKit
import Vision

enum ImageProcessingError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        "The asset could not be decoded as an image."
    }
}

enum ImageProcessing {
    static func thumbnailPNG(from imageData: Data, maxDimension: CGFloat = 512) throws -> Data {
        guard let source = NSBitmapImageRep(data: imageData) else {
            throw ImageProcessingError.unreadableImage
        }
        let width = CGFloat(source.pixelsWide)
        let height = CGFloat(source.pixelsHigh)
        let scale = min(1, maxDimension / max(width, height, 1))
        let targetSize = NSSize(width: max(1, width * scale), height: max(1, height * scale))

        let image = NSImage(size: targetSize)
        image.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: targetSize))
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw ImageProcessingError.unreadableImage
        }
        return png
    }

    static func recognizeText(in imageData: Data) throws -> String {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageProcessingError.unreadableImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
