import Foundation

typealias FragmentID = UUID
typealias AssetID = UUID
typealias JobID = UUID

enum SourceType: String, CaseIterable {
    case text
    case url
    case screenshot
    case image
}

enum FragmentStatus: String {
    case captured
    case processing
    case ready
    case failed
}

enum AssetKind: String {
    case text
    case url
    case image
}

enum JobStatus: String {
    case pending
    case running
    case succeeded
    case failed
}
