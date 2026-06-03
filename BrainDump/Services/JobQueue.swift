import Foundation
import Observation

@Observable
@MainActor
final class JobQueue {
    private let database: Database
    private(set) var pendingCount = 0

    init(database: Database) {
        self.database = database
    }

    func refresh() {
        let rows = try? database.query(
            "SELECT COUNT(*) FROM jobs WHERE status = ?;",
            bind: { bindText(JobStatus.pending.rawValue, to: $0, at: 1) },
            map: { Int(columnInt64($0, at: 0)) }
        )
        pendingCount = rows?.first ?? 0
    }
}
