import Foundation

struct AppStorageLocator {
    let root: URL
    let databaseURL: URL
    let blobsURL: URL
    let thumbnailsURL: URL
    let exportsURL: URL
    let logsURL: URL

    static func live(fileManager: FileManager = .default) throws -> AppStorageLocator {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent("BrainDump", isDirectory: true)
        let locator = AppStorageLocator(
            root: root,
            databaseURL: root.appendingPathComponent("BrainDump.sqlite"),
            blobsURL: root.appendingPathComponent("blobs", isDirectory: true),
            thumbnailsURL: root.appendingPathComponent("thumbnails", isDirectory: true),
            exportsURL: root.appendingPathComponent("exports", isDirectory: true),
            logsURL: root.appendingPathComponent("logs", isDirectory: true)
        )

        for directory in [locator.root, locator.blobsURL, locator.thumbnailsURL, locator.exportsURL, locator.logsURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return locator
    }
}
