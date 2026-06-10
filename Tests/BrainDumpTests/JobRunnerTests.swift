import AppKit
import Foundation
import GRDB
import Testing
@testable import BrainDump

@MainActor
struct JobRunnerTests {
    @Test
    func imageJobsProduceThumbnailAndOCRText() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let fragmentID = try env.store.captureImage(Self.textImagePNG("BRAIN DUMP"), sourceType: .screenshot)
        let runner = JobRunner(database: env.database, thumbnailsURL: env.thumbnailsURL)
        let processed = await runner.processAllPending()

        #expect(processed == 2)

        let assetID = env.store.fragments.first?.primaryAssetID
        #expect(assetID != nil)
        if let assetID {
            let thumbnail = env.thumbnailsURL.appendingPathComponent("\(assetID.uuidString).png")
            #expect(FileManager.default.fileExists(atPath: thumbnail.path))
        }

        let extracted = env.store.extractedText(for: fragmentID)
        #expect(extracted?.contains("BRAIN") == true)

        env.store.loadFragments()
        #expect(env.store.fragments.first?.status == .ready)

        let unhandled = try env.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jobs WHERE status = 'pending'")
        }
        #expect(unhandled == 1)
    }

    @Test
    func missingAssetRetriesThenFails() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let fragmentID = try env.store.captureImage(Self.textImagePNG("X"), sourceType: .image)
        let assetPath = env.store.primaryAssetLocalPath(for: fragmentID)
        #expect(assetPath != nil)
        if let assetPath {
            try FileManager.default.removeItem(atPath: assetPath)
        }
        try env.database.write { db in
            try db.execute(sql: "UPDATE jobs SET max_attempts = 1")
        }

        let runner = JobRunner(database: env.database, thumbnailsURL: env.thumbnailsURL)
        await runner.processAllPending()

        let failed = try env.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jobs WHERE status = 'failed' AND last_error IS NOT NULL")
        }
        #expect(failed == 2)

        env.store.loadFragments()
        #expect(env.store.fragments.first?.status == .failed)
    }

    @Test
    func failedAttemptBacksOffUntilAvailableAt() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let fragmentID = try env.store.captureImage(Self.textImagePNG("X"), sourceType: .image)
        if let assetPath = env.store.primaryAssetLocalPath(for: fragmentID) {
            try FileManager.default.removeItem(atPath: assetPath)
        }

        let runner = JobRunner(database: env.database, thumbnailsURL: env.thumbnailsURL)
        await runner.processAllPending()

        let rows = try env.database.read { db in
            try Row.fetchAll(db, sql: "SELECT status, attempts, available_at FROM jobs WHERE type IN ('generate_thumbnail', 'ocr_image')")
        }
        #expect(rows.count == 2)
        for row in rows {
            #expect(row["status"] == "pending")
            #expect(row["attempts"] == 1)
            #expect(DateFormatting.date(from: row["available_at"]) > Date())
        }
    }

    @Test
    func kickDrivesProcessingWithoutPolling() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        let runner = JobRunner(database: env.database, thumbnailsURL: env.thumbnailsURL)
        env.store.onJobsEnqueued = { [weak runner] in runner?.kick() }
        runner.start()
        defer { runner.stop() }

        try env.store.captureImage(Self.textImagePNG("KICK"), sourceType: .image)

        for _ in 0..<100 {
            let remaining = try env.database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jobs WHERE type IN ('generate_thumbnail', 'ocr_image') AND status != 'succeeded'")
            } ?? 0
            if remaining == 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        let succeeded = try env.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jobs WHERE status = 'succeeded'")
        }
        #expect(succeeded == 2)
    }

    @Test
    func staleRunningJobsResetOnStart() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        try env.store.captureImage(Self.textImagePNG("X"), sourceType: .image)
        try env.database.write { db in
            try db.execute(sql: "UPDATE jobs SET status = 'running'")
        }

        let runner = JobRunner(database: env.database, thumbnailsURL: env.thumbnailsURL)
        runner.start()
        runner.stop()

        let running = try env.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jobs WHERE status = 'running'")
        }
        #expect(running == 0)
    }

    @Test
    func urlMetadataJobInsertsExtractionAndUpdatesTitle() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        try env.store.capture(rawInput: "https://example.com/article")

        let runner = JobRunner(database: env.database, thumbnailsURL: env.thumbnailsURL)
        runner.pageFetcher = { _ in
            """
            <html><head>
            <title>Example Article</title>
            <meta name="description" content="A story about brains.">
            <meta property="og:image" content="https://example.com/og.png">
            </head></html>
            """
        }
        let processed = await runner.processAllPending()
        #expect(processed == 1)

        let row = try env.database.read { db in
            try Row.fetchOne(db, sql: "SELECT content_text, metadata_json FROM extractions WHERE kind = 'url_metadata'")
        }
        #expect(row != nil)
        if let row {
            #expect((row["content_text"] as String?) == "Example Article\nA story about brains.")
            let json = try JSONSerialization.jsonObject(with: Data(((row["metadata_json"] as String?) ?? "{}").utf8)) as? [String: String]
            #expect(json?["title"] == "Example Article")
            #expect(json?["description"] == "A story about brains.")
            #expect(json?["og_image"] == "https://example.com/og.png")
        }

        env.store.loadFragments()
        #expect(env.store.fragments.first?.title == "Example Article")
        #expect(env.store.fragments.first?.status == .ready)
    }

    @Test
    func urlMetadataFetchFailureBacksOffForRetry() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }

        try env.store.capture(rawInput: "https://example.com/down")

        let runner = JobRunner(database: env.database, thumbnailsURL: env.thumbnailsURL)
        runner.pageFetcher = { _ in throw URLError(.timedOut) }
        await runner.processAllPending()

        let row = try env.database.read { db in
            try Row.fetchOne(db, sql: "SELECT status, attempts, available_at, last_error FROM jobs WHERE type = 'extract_url_metadata'")
        }
        #expect(row != nil)
        if let row {
            #expect(row["status"] == "pending")
            #expect(row["attempts"] == 1)
            #expect((row["last_error"] as String?) != nil)
            #expect(DateFormatting.date(from: row["available_at"]) > Date())
        }

        env.store.loadFragments()
        #expect(env.store.fragments.first?.status == .processing)

        let extractions = try env.database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM extractions")
        }
        #expect(extractions == 0)
    }

    private static func textImagePNG(_ text: String) -> Data {
        let size = NSSize(width: 400, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 48),
            .foregroundColor: NSColor.black
        ]
        NSString(string: text).draw(at: NSPoint(x: 20, y: 30), withAttributes: attributes)
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }
}

@MainActor
private struct TestEnvironment {
    let root: URL
    let database: AppDatabase
    let store: FragmentStore
    let thumbnailsURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainDumpJobTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        thumbnailsURL = root.appendingPathComponent("thumbnails", isDirectory: true)
        database = try AppDatabase(path: root.appendingPathComponent("BrainDump.sqlite").path)
        try database.migrate()
        store = FragmentStore(database: database, blobStore: BlobStore(root: root.appendingPathComponent("blobs", isDirectory: true)))
        store.thumbnailsRoot = thumbnailsURL
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
