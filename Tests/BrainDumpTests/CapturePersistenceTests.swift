import Foundation
import Testing
@testable import BrainDump

@MainActor
struct CapturePersistenceTests {
    @Test
    func textAndURLCapturesPersistWithAssetsAndJobs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainDumpTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = AppStorageLocator(
            root: root,
            databaseURL: root.appendingPathComponent("BrainDump.sqlite"),
            blobsURL: root.appendingPathComponent("blobs", isDirectory: true),
            thumbnailsURL: root.appendingPathComponent("thumbnails", isDirectory: true),
            exportsURL: root.appendingPathComponent("exports", isDirectory: true),
            logsURL: root.appendingPathComponent("logs", isDirectory: true)
        )
        for directory in [storage.root, storage.blobsURL, storage.thumbnailsURL, storage.exportsURL, storage.logsURL] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let firstDatabase = try Database(path: storage.databaseURL.path)
        try firstDatabase.migrate()
        let firstStore = FragmentStore(database: firstDatabase, blobStore: BlobStore(root: storage.blobsURL))
        try firstStore.capture(rawInput: "A local-first native Mac capture palette note")
        try firstStore.capture(rawInput: "https://example.com/brain-dump")

        #expect(firstStore.fragments.count == 2)
        #expect(firstStore.fragments.map(\.sourceType).contains(.text))
        #expect(firstStore.fragments.map(\.sourceType).contains(.url))

        let persistedDatabase = try Database(path: storage.databaseURL.path)
        try persistedDatabase.migrate()
        let persistedStore = FragmentStore(database: persistedDatabase, blobStore: BlobStore(root: storage.blobsURL))
        persistedStore.loadFragments()

        #expect(persistedStore.fragments.count == 2)

        let assetCount = try persistedDatabase.query("SELECT COUNT(*) FROM assets;") {
            Int(columnInt64($0, at: 0))
        }.first
        let jobCount = try persistedDatabase.query("SELECT COUNT(*) FROM jobs;") {
            Int(columnInt64($0, at: 0))
        }.first

        #expect(assetCount == 2)
        #expect(jobCount == 4)

        let blobFiles = try FileManager.default.subpathsOfDirectory(atPath: storage.blobsURL.path)
            .filter { $0.hasSuffix(".txt") }
        #expect(blobFiles.count == 2)
    }
}
