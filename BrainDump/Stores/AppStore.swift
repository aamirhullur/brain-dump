import Foundation
import Observation

@Observable
@MainActor
final class AppStore {
    let storage: AppStorageLocator
    let fragmentStore: FragmentStore
    private let database: Database

    var isMemoryInletPresented = false
    var memoryInletRequestCount = 0
    var startupError: String?

    init() {
        do {
            let storage = try AppStorageLocator.live()
            let database = try Database(path: storage.databaseURL.path)
            try database.migrate()
            let blobStore = BlobStore(root: storage.blobsURL)

            self.storage = storage
            self.database = database
            self.fragmentStore = FragmentStore(database: database, blobStore: blobStore)
            self.fragmentStore.loadFragments()
        } catch {
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BrainDump", isDirectory: true)
            self.storage = AppStorageLocator(
                root: fallback,
                databaseURL: fallback.appendingPathComponent("BrainDump.sqlite"),
                blobsURL: fallback.appendingPathComponent("blobs", isDirectory: true),
                thumbnailsURL: fallback.appendingPathComponent("thumbnails", isDirectory: true),
                exportsURL: fallback.appendingPathComponent("exports", isDirectory: true),
                logsURL: fallback.appendingPathComponent("logs", isDirectory: true)
            )
            self.database = try! Database(path: ":memory:")
            self.fragmentStore = FragmentStore(database: database, blobStore: BlobStore(root: storage.blobsURL))
            self.startupError = error.localizedDescription
        }
    }

    func showMemoryInlet() {
        isMemoryInletPresented = true
        memoryInletRequestCount += 1
    }

    func hideMemoryInlet() {
        isMemoryInletPresented = false
    }
}
