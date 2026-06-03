import Foundation

struct Asset: Identifiable, Equatable {
    let id: AssetID
    let fragmentID: FragmentID
    let kind: AssetKind
    let sha256: String
    let originalFilename: String?
    let mimeType: String?
    let byteSize: Int64
    let localPath: String?
    let sourceURL: URL?
    let createdAt: Date
}
