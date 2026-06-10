import Foundation
import GRDB

@MainActor
final class JobRunner {
    static let handledTypes = ["generate_thumbnail", "ocr_image"]
    static let handledTypesJSON = String(data: try! JSONEncoder().encode(handledTypes), encoding: .utf8)!

    private let database: AppDatabase
    private let thumbnailsURL: URL
    private let onFragmentsChanged: () -> Void
    private var loopTask: Task<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var pendingKick = false
    private var retryWakeTask: Task<Void, Never>?

    init(
        database: AppDatabase,
        thumbnailsURL: URL,
        onFragmentsChanged: @escaping () -> Void = {}
    ) {
        self.database = database
        self.thumbnailsURL = thumbnailsURL
        self.onFragmentsChanged = onFragmentsChanged
    }

    deinit {
        loopTask?.cancel()
        retryWakeTask?.cancel()
        waiter?.resume()
    }

    func start() {
        guard loopTask == nil else { return }
        resetStaleRunningJobs()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.processAllPending()
                if Task.isCancelled { return }
                await self.waitForWork()
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        retryWakeTask?.cancel()
        retryWakeTask = nil
        wake()
    }

    /// Call after enqueueing jobs so the runner picks them up immediately.
    func kick() {
        wake()
    }

    @discardableResult
    func processAllPending() async -> Int {
        var processed = 0
        while await processNextJob() {
            processed += 1
        }
        return processed
    }

    private func wake() {
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else {
            pendingKick = true
        }
    }

    private func waitForWork() async {
        if pendingKick {
            pendingKick = false
            return
        }

        if let retryDelay = nextRetryDelay() {
            retryWakeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(retryDelay))
                guard !Task.isCancelled else { return }
                self?.wake()
            }
        }

        await withCheckedContinuation { continuation in
            if pendingKick {
                pendingKick = false
                continuation.resume()
            } else {
                waiter = continuation
            }
        }
        retryWakeTask?.cancel()
        retryWakeTask = nil
    }

    private func nextRetryDelay() -> TimeInterval? {
        let availableAt = try? database.read { db in
            try String.fetchOne(
                db,
                sql: """
                SELECT MIN(available_at) FROM jobs
                WHERE status = 'pending' AND type IN (SELECT value FROM json_each(:types))
                """,
                arguments: ["types": Self.handledTypesJSON]
            )
        }
        guard let earliest = availableAt ?? nil else { return nil }
        return max(0.1, DateFormatting.date(from: earliest).timeIntervalSinceNow)
    }

    private func processNextJob() async -> Bool {
        guard let job = claimNextJob() else { return false }

        do {
            try await execute(job)
            try complete(job, status: .succeeded, error: nil)
        } catch {
            let exhausted = job.attempts >= job.maxAttempts
            try? complete(job, status: exhausted ? .failed : .pending, error: error.localizedDescription)
        }

        updateFragmentStatus(for: job.fragmentID)
        onFragmentsChanged()
        return true
    }

    private func execute(_ job: ClaimedJob) async throws {
        guard let assetPath = job.assetPath else {
            throw JobError.missingAsset
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: assetPath))

        switch job.type {
        case "generate_thumbnail":
            guard let assetID = job.assetID else { throw JobError.missingAsset }
            let thumbnail = try await Task.detached(priority: .utility) {
                try ImageProcessing.thumbnailPNG(from: data)
            }.value
            try FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
            try thumbnail.write(to: thumbnailsURL.appendingPathComponent("\(assetID.uuidString).png"), options: [.atomic])
        case "ocr_image":
            let text = try await Task.detached(priority: .utility) {
                try ImageProcessing.recognizeText(in: data)
            }.value
            try insertExtraction(kind: "ocr_text", text: text, job: job)
        default:
            throw JobError.unhandledType(job.type)
        }
    }

    private struct ClaimedJob {
        let id: String
        let type: String
        let attempts: Int
        let maxAttempts: Int
        let fragmentID: FragmentID?
        let assetID: AssetID?
        let assetPath: String?
    }

    private enum JobError: LocalizedError {
        case missingAsset
        case unhandledType(String)

        var errorDescription: String? {
            switch self {
            case .missingAsset:
                return "The job has no stored asset to process."
            case .unhandledType(let type):
                return "No handler for job type \(type)."
            }
        }
    }

    private func claimNextJob() -> ClaimedJob? {
        let now = DateFormatting.string(from: Date())
        return try? database.write { db -> ClaimedJob? in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT j.id, j.type, j.attempts, j.max_attempts, j.fragment_id, j.asset_id, a.local_path
                FROM jobs j
                LEFT JOIN assets a ON a.id = j.asset_id
                WHERE j.status = 'pending' AND j.available_at <= :now
                  AND j.type IN (SELECT value FROM json_each(:types))
                ORDER BY j.created_at
                LIMIT 1
                """,
                arguments: ["now": now, "types": Self.handledTypesJSON]
            ) else {
                return nil
            }

            let job = ClaimedJob(
                id: row["id"],
                type: row["type"],
                attempts: (row["attempts"] as Int) + 1,
                maxAttempts: row["max_attempts"],
                fragmentID: (row["fragment_id"] as String?).flatMap(UUID.init(uuidString:)),
                assetID: (row["asset_id"] as String?).flatMap(UUID.init(uuidString:)),
                assetPath: row["local_path"]
            )

            try db.execute(
                sql: """
                UPDATE jobs
                SET status = 'running', attempts = :attempts, started_at = :now, updated_at = :now
                WHERE id = :id
                """,
                arguments: ["attempts": job.attempts, "now": now, "id": job.id]
            )
            return job
        }
    }

    private func complete(_ job: ClaimedJob, status: JobStatus, error: String?) throws {
        let now = Date()
        let retryDelay = TimeInterval(pow(2, Double(job.attempts)) * 5)
        let availableAt = status == .pending ? now.addingTimeInterval(retryDelay) : now
        try database.write { db in
            try db.execute(
                sql: """
                UPDATE jobs
                SET status = :status, finished_at = :finished_at, updated_at = :now, available_at = :available_at, last_error = :error
                WHERE id = :id
                """,
                arguments: [
                    "status": status.rawValue,
                    "finished_at": status == .pending ? nil : DateFormatting.string(from: now),
                    "now": DateFormatting.string(from: now),
                    "available_at": DateFormatting.string(from: availableAt),
                    "error": error,
                    "id": job.id
                ]
            )
        }
    }

    private func insertExtraction(kind: String, text: String, job: ClaimedJob) throws {
        guard let fragmentID = job.fragmentID else { return }
        try database.write { db in
            try db.execute(
                sql: """
                INSERT INTO extractions (id, fragment_id, asset_id, kind, content_text, metadata_json, created_at)
                VALUES (:id, :fragment_id, :asset_id, :kind, :content_text, '{}', :created_at)
                """,
                arguments: [
                    "id": UUID().uuidString,
                    "fragment_id": fragmentID.uuidString,
                    "asset_id": job.assetID?.uuidString,
                    "kind": kind,
                    "content_text": text,
                    "created_at": DateFormatting.string(from: Date())
                ]
            )
        }
    }

    private func updateFragmentStatus(for fragmentID: FragmentID?) {
        guard let fragmentID else { return }
        try? database.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                  SUM(CASE WHEN status IN ('pending', 'running') THEN 1 ELSE 0 END) AS active,
                  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
                FROM jobs
                WHERE fragment_id = :id AND type IN (SELECT value FROM json_each(:types))
                """,
                arguments: ["id": fragmentID.uuidString, "types": Self.handledTypesJSON]
            ) else {
                return
            }

            let newStatus: FragmentStatus
            if (row["active"] as Int? ?? 0) > 0 {
                newStatus = .processing
            } else if (row["failed"] as Int? ?? 0) > 0 {
                newStatus = .failed
            } else {
                newStatus = .ready
            }
            try db.execute(
                sql: "UPDATE fragments SET status = :status, updated_at = :now WHERE id = :id",
                arguments: [
                    "status": newStatus.rawValue,
                    "now": DateFormatting.string(from: Date()),
                    "id": fragmentID.uuidString
                ]
            )
        }
    }

    private func resetStaleRunningJobs() {
        try? database.write { db in
            try db.execute(
                sql: "UPDATE jobs SET status = 'pending', updated_at = :now WHERE status = 'running'",
                arguments: ["now": DateFormatting.string(from: Date())]
            )
        }
    }
}
