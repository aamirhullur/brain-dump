import Foundation

struct StoredAssetRecord {
    let fileURL: URL
    let sha256: String
}

struct BlobStore {
    let root: URL

    func writeTextAsset(_ data: Data, fragmentID: FragmentID, assetID: AssetID) throws -> StoredAssetRecord {
        try writeAsset(data, fragmentID: fragmentID, assetID: assetID, fileExtension: "txt")
    }

    func writeAsset(_ data: Data, fragmentID: FragmentID, assetID: AssetID, fileExtension: String) throws -> StoredAssetRecord {
        let fragmentDirectory = root.appendingPathComponent(fragmentID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: fragmentDirectory, withIntermediateDirectories: true)
        let fileURL = fragmentDirectory.appendingPathComponent("\(assetID.uuidString).\(fileExtension)")
        try data.write(to: fileURL, options: [.atomic])
        return StoredAssetRecord(fileURL: fileURL, sha256: Hashing.sha256Hex(data))
    }
}

enum URLDetector {
    static func url(from input: String) -> URL? {
        if let url = URL(string: input), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return url
        }
        if input.contains("."), !input.contains(" "), let url = URL(string: "https://\(input)") {
            return url
        }
        return nil
    }
}
