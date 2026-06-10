import AppKit
import Foundation
import Testing
@testable import BrainDump

@MainActor
struct ImageCaptureTests {
    @Test
    func imageCapturePersistsAssetAndJobs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainDumpImageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let database = try Database(path: root.appendingPathComponent("BrainDump.sqlite").path)
        try database.migrate()
        let store = FragmentStore(database: database, blobStore: BlobStore(root: root.appendingPathComponent("blobs", isDirectory: true)))

        let pngData = Self.tinyPNGData()
        let fragmentID = try store.captureImage(
            pngData,
            sourceType: .screenshot,
            originalFilename: "region.png"
        )

        #expect(store.fragments.count == 1)
        #expect(store.fragments.first?.sourceType == .screenshot)
        #expect(store.selectedFragmentID == fragmentID)

        let assetPath = store.primaryAssetLocalPath(for: fragmentID)
        #expect(assetPath != nil)
        if let assetPath {
            let stored = try Data(contentsOf: URL(fileURLWithPath: assetPath))
            #expect(stored == pngData)
        }

        let jobTypes = try database.query(
            "SELECT type FROM jobs WHERE fragment_id = ? ORDER BY type;",
            bind: { bindText(fragmentID.uuidString, to: $0, at: 1) },
            map: { columnText($0, at: 0) }
        )
        #expect(jobTypes == ["generate_thumbnail", "ocr_image", "prepare_fragment_card"])
    }

    @Test
    func emptyImageDataIsRejected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainDumpImageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let database = try Database(path: root.appendingPathComponent("BrainDump.sqlite").path)
        try database.migrate()
        let store = FragmentStore(database: database, blobStore: BlobStore(root: root.appendingPathComponent("blobs", isDirectory: true)))

        #expect(throws: CaptureError.self) {
            try store.captureImage(Data(), sourceType: .image)
        }
        #expect(store.fragments.isEmpty)
    }

    @Test
    func screenshotShortcutDetectorMatchesOptionShiftTwo() {
        #expect(ScreenshotShortcutDetector.matches(keyCode: 19, modifierFlags: [.option, .shift]))
        #expect(!ScreenshotShortcutDetector.matches(keyCode: 19, modifierFlags: [.option]))
        #expect(!ScreenshotShortcutDetector.matches(keyCode: 19, modifierFlags: [.option, .shift, .command]))
        #expect(!ScreenshotShortcutDetector.matches(keyCode: 18, modifierFlags: [.option, .shift]))
    }

    private static func tinyPNGData() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }
}
