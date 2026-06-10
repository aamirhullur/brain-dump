import Foundation
import GRDB
import Testing
@testable import BrainDump

@MainActor
private struct StoreFixture {
    let root: URL
    let databaseURL: URL
    let blobsURL: URL
    let database: AppDatabase
    let store: FragmentStore

    static func make() throws -> StoreFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainDumpStoreTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = root.appendingPathComponent("BrainDump.sqlite")
        let blobsURL = root.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)

        let database = try AppDatabase(path: databaseURL.path)
        try database.migrate()
        let store = FragmentStore(database: database, blobStore: BlobStore(root: blobsURL))
        return StoreFixture(root: root, databaseURL: databaseURL, blobsURL: blobsURL, database: database, store: store)
    }

    func reopenStore() throws -> FragmentStore {
        let database = try AppDatabase(path: databaseURL.path)
        try database.migrate()
        let store = FragmentStore(database: database, blobStore: BlobStore(root: blobsURL))
        store.loadFragments()
        return store
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
struct FragmentStoreTests {
    @Test
    func bookmarkedAtColumnExistsAndDefaultsToNull() throws {
        let fixture = try StoreFixture.make()
        defer { fixture.tearDown() }

        let columns = try fixture.database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(fragments)").map { $0["name"] as String }
        }
        #expect(columns.contains("bookmarked_at"))

        try fixture.store.capture(rawInput: "remember this")
        let fragment = try #require(fixture.store.fragments.first)
        #expect(fragment.bookmarkedAt == nil)
        #expect(!fragment.isBookmarked)
    }

    @Test
    func toggleBookmarkPersistsAcrossReload() throws {
        let fixture = try StoreFixture.make()
        defer { fixture.tearDown() }

        try fixture.store.capture(rawInput: "bookmark me")
        let fragmentID = try #require(fixture.store.fragments.first).id

        fixture.store.toggleBookmark(fragmentID)
        #expect(fixture.store.isBookmarked(fragmentID))

        let reloaded = try fixture.reopenStore()
        #expect(reloaded.fragments.first?.isBookmarked == true)

        fixture.store.toggleBookmark(fragmentID)
        #expect(!fixture.store.isBookmarked(fragmentID))

        let reloadedAgain = try fixture.reopenStore()
        #expect(reloadedAgain.fragments.first?.isBookmarked == false)
    }

    @Test
    func softDeleteHidesFragmentButKeepsRowAndBlob() throws {
        let fixture = try StoreFixture.make()
        defer { fixture.tearDown() }

        try fixture.store.capture(rawInput: "keep this one")
        try fixture.store.capture(rawInput: "delete this one")
        let target = try #require(fixture.store.fragments.first)
        fixture.store.selectedFragmentID = target.id

        fixture.store.softDelete(target.id)

        #expect(fixture.store.fragments.count == 1)
        #expect(fixture.store.fragments.allSatisfy { $0.id != target.id })
        #expect(fixture.store.selectedFragmentID == fixture.store.fragments.first?.id)

        let (totalRows, deletedAt) = try fixture.database.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM fragments"),
                try String.fetchOne(
                    db,
                    sql: "SELECT deleted_at FROM fragments WHERE id = ?",
                    arguments: [target.id.uuidString]
                )
            )
        }
        #expect(totalRows == 2)
        #expect(deletedAt != nil)

        let blobFiles = try FileManager.default.subpathsOfDirectory(atPath: fixture.blobsURL.path)
            .filter { $0.hasSuffix(".txt") }
        #expect(blobFiles.count == 2)

        let reloaded = try fixture.reopenStore()
        #expect(reloaded.fragments.count == 1)
    }

    @Test
    func annotationUpdatePersistsAndPreservesCapturedEvidence() throws {
        let fixture = try StoreFixture.make()
        defer { fixture.tearDown() }

        try fixture.store.capture(rawInput: "original capture text")
        let fragmentID = try #require(fixture.store.fragments.first).id

        fixture.store.updateAnnotation("my annotation", for: fragmentID)
        #expect(fixture.store.fragments.first?.annotation == "my annotation")
        #expect(fixture.store.fragments.first?.userNote == "original capture text")

        let reloaded = try fixture.reopenStore()
        #expect(reloaded.fragments.first?.annotation == "my annotation")
        #expect(reloaded.fragments.first?.userNote == "original capture text")

        fixture.store.updateAnnotation("   ", for: fragmentID)
        let reloadedBlank = try fixture.reopenStore()
        #expect(reloadedBlank.fragments.first?.annotation == nil)
        #expect(reloadedBlank.fragments.first?.userNote == "original capture text")
    }

    @Test
    func sectionFilteringProducesPerSectionCounts() throws {
        let fixture = try StoreFixture.make()
        defer { fixture.tearDown() }

        try fixture.store.capture(rawInput: "a plain text note")
        try fixture.store.capture(rawInput: "example.com/reference")
        try fixture.store.captureImage(Data([0x89, 0x50, 0x4E, 0x47]), sourceType: .screenshot)

        func count(_ section: AppSection) -> Int {
            fixture.store.fragments.filter { section.includes($0) }.count
        }

        #expect(count(.allEvidence) == 3)
        #expect(count(.text) == 1)
        #expect(count(.links) == 1)
        #expect(count(.screenshots) == 1)
        #expect(count(.today) == 3)
        #expect(count(.unprocessed) == 3)
        #expect(count(.bookmarks) == 0)

        let textFragment = try #require(fixture.store.fragments.first { $0.sourceType == .text })
        fixture.store.toggleBookmark(textFragment.id)
        #expect(count(.bookmarks) == 1)
        #expect(count(.allEvidence) == 3)
    }
}
