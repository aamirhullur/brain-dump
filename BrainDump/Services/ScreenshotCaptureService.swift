import AppKit
import Foundation

@MainActor
struct ScreenshotCaptureService {
    enum CaptureResult {
        case captured(Data)
        case cancelled
        case failed(String)
    }

    /// Cancelling the region selection (escape) is not an error.
    func captureInteractiveRegion() async -> CaptureResult {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainDump-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", fileURL.path]

        let launchError: String? = await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume(returning: nil)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: error.localizedDescription)
            }
        }
        if let launchError {
            return .failed(launchError)
        }

        guard process.terminationStatus == 0 else {
            return .failed("screencapture exited with status \(process.terminationStatus)")
        }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return .cancelled
        }
        return .captured(data)
    }
}
