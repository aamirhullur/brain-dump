import Foundation

struct Job: Identifiable, Equatable {
    let id: JobID
    let createdAt: Date
    let updatedAt: Date
    let type: String
    let status: JobStatus
    let attempts: Int
    let maxAttempts: Int
    let availableAt: Date
    let fragmentID: FragmentID?
    let assetID: AssetID?
    let payloadJSON: String
    let lastError: String?
}
