import AppKit
import Foundation
import UniformTypeIdentifiers

struct IngestableImage {
    let data: Data
    let originalFilename: String?
    let fileExtension: String
    let mimeType: String
}

enum ImageIngest {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "webp", "bmp"]

    static func clipboardImage(from pasteboard: NSPasteboard = .general) -> IngestableImage? {
        if let data = pasteboard.data(forType: .png), !data.isEmpty {
            return IngestableImage(data: data, originalFilename: nil, fileExtension: "png", mimeType: "image/png")
        }
        if let data = pasteboard.data(forType: .tiff), !data.isEmpty {
            // Normalize TIFF clipboard data to PNG so the stored asset is broadly readable.
            if let png = pngData(fromTIFF: data) {
                return IngestableImage(data: png, originalFilename: nil, fileExtension: "png", mimeType: "image/png")
            }
        }
        return nil
    }

    static func image(fromFileURL url: URL) -> IngestableImage? {
        let ext = url.pathExtension.lowercased()
        guard imageExtensions.contains(ext), let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }
        return IngestableImage(
            data: data,
            originalFilename: url.lastPathComponent,
            fileExtension: ext,
            mimeType: mimeType(forExtension: ext)
        )
    }

    @MainActor
    static func images(from providers: [NSItemProvider]) async -> [IngestableImage] {
        var images: [IngestableImage] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await fileURL(from: provider), let image = image(fromFileURL: url) {
                    images.append(image)
                }
                continue
            }
            for type in [UTType.png, UTType.tiff, UTType.image] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                if let data = await data(from: provider, type: type), !data.isEmpty {
                    if type == .png {
                        images.append(IngestableImage(data: data, originalFilename: nil, fileExtension: "png", mimeType: "image/png"))
                    } else if let png = pngData(fromTIFF: data) ?? pngData(fromArbitraryImageData: data) {
                        images.append(IngestableImage(data: png, originalFilename: nil, fileExtension: "png", mimeType: "image/png"))
                    }
                }
                break
            }
        }
        return images
    }

    static func mimeType(forExtension ext: String) -> String {
        UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    @MainActor
    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    @MainActor
    private static func data(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func pngData(fromTIFF data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func pngData(fromArbitraryImageData data: Data) -> Data? {
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation else { return nil }
        return pngData(fromTIFF: tiff)
    }
}
