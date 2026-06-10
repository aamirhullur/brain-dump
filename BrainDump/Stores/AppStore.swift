import Foundation
import Observation

@Observable
@MainActor
final class AppStore {
    let storage: AppStorageLocator
    let fragmentStore: FragmentStore
    private let database: Database
    private var jobRunner: JobRunner?

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
            self.fragmentStore.thumbnailsRoot = storage.thumbnailsURL
            self.fragmentStore.loadFragments()

            let runner = JobRunner(
                database: database,
                thumbnailsURL: storage.thumbnailsURL,
                onFragmentsChanged: { [weak fragmentStore = self.fragmentStore] in
                    fragmentStore?.loadFragments()
                }
            )
            self.jobRunner = runner
            self.fragmentStore.onJobsEnqueued = { [weak runner] in
                runner?.kick()
            }
            runner.start()
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

    private(set) var isCapturingScreenshot = false
    var captureError: CaptureFailure?

    struct CaptureFailure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let needsScreenRecordingPermission: Bool
    }

    func captureScreenshot() {
        guard !isCapturingScreenshot else { return }
        isCapturingScreenshot = true
        Task { @MainActor in
            defer { isCapturingScreenshot = false }
            let result = await ScreenshotCaptureService().captureInteractiveRegion()
            switch result {
            case .captured(let data):
                do {
                    try fragmentStore.captureImage(data, sourceType: .screenshot)
                } catch {
                    captureError = CaptureFailure(
                        title: "Screenshot Not Saved",
                        message: "The screenshot was captured but could not be stored: \(error.localizedDescription)",
                        needsScreenRecordingPermission: false
                    )
                }
            case .cancelled:
                break
            case .failed(let message):
                // screencapture exits 1 when Screen Recording permission is
                // missing or stale (e.g. revoked by a rebuild's new signature).
                let isPermissionFailure = message.contains("status 1")
                captureError = CaptureFailure(
                    title: "Screenshot Failed",
                    message: isPermissionFailure
                        ? "macOS blocked the capture. Enable Brain Dump under System Settings → Privacy & Security → Screen & System Audio Recording. If it is already enabled, toggle it off and on; the permission goes stale when the app is rebuilt."
                        : message,
                    needsScreenRecordingPermission: isPermissionFailure
                )
            }
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
