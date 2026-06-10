import Foundation
import GRDB
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

        let firstDatabase = try AppDatabase(path: storage.databaseURL.path)
        try firstDatabase.migrate()
        let firstStore = FragmentStore(database: firstDatabase, blobStore: BlobStore(root: storage.blobsURL))
        try firstStore.capture(rawInput: "A local-first native Mac memory inlet note")
        try firstStore.capture(rawInput: "example.com/brain-dump")

        #expect(firstStore.fragments.count == 2)
        #expect(firstStore.fragments.map(\.sourceType).contains(.text))
        #expect(firstStore.fragments.map(\.sourceType).contains(.url))

        let persistedDatabase = try AppDatabase(path: storage.databaseURL.path)
        try persistedDatabase.migrate()
        let persistedStore = FragmentStore(database: persistedDatabase, blobStore: BlobStore(root: storage.blobsURL))
        persistedStore.loadFragments()

        #expect(persistedStore.fragments.count == 2)

        let (assetCount, jobCount, sourceURLs) = try persistedDatabase.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM assets"),
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jobs"),
                try String.fetchAll(db, sql: "SELECT source_url FROM assets WHERE kind = 'url'")
            )
        }

        #expect(assetCount == 2)
        #expect(jobCount == 4)
        #expect(sourceURLs == ["https://example.com/brain-dump"])

        let blobFiles = try FileManager.default.subpathsOfDirectory(atPath: storage.blobsURL.path)
            .filter { $0.hasSuffix(".txt") }
        #expect(blobFiles.count == 2)
    }
}
