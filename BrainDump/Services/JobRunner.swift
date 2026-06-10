import Foundation

@MainActor
final class JobRunner {
    static let handledTypes = ["generate_thumbnail", "ocr_image"]

    private let database: Database
    private let thumbnailsURL: URL
    private let onFragmentsChanged: () -> Void
    private var loopTask: Task<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var pendingKick = false
    private var retryWakeTask: Task<Void, Never>?

    init(
        database: Database,
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
        let placeholders = Self.handledTypes.map { _ in "?" }.joined(separator: ", ")
        let rows = try? database.query(
            "SELECT MIN(available_at) FROM jobs WHERE status = 'pending' AND type IN (\(placeholders));",
            bind: { statement in
                for (index, type) in Self.handledTypes.enumerated() {
                    bindText(type, to: statement, at: Int32(index + 1))
                }
            },
            map: { columnOptionalText($0, at: 0) }
        )
        guard let availableAt = rows?.first ?? nil else { return nil }
        return max(0.1, DateFormatting.date(from: availableAt).timeIntervalSinceNow)
    }

    @discardableResult
    func processAllPending() async -> Int {
        var processed = 0
        while await processNextJob() {
            processed += 1
        }
        return processed
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
        let placeholders = Self.handledTypes.map { _ in "?" }.joined(separator: ", ")
        let rows = try? database.query(
            """
            SELECT j.id, j.type, j.attempts, j.max_attempts, j.fragment_id, j.asset_id, a.local_path
            FROM jobs j
            LEFT JOIN assets a ON a.id = j.asset_id
            WHERE j.status = 'pending' AND j.available_at <= ? AND j.type IN (\(placeholders))
            ORDER BY j.created_at
            LIMIT 1;
            """,
            bind: { statement in
                bindText(now, to: statement, at: 1)
                for (index, type) in Self.handledTypes.enumerated() {
                    bindText(type, to: statement, at: Int32(index + 2))
                }
            },
            map: { statement in
                ClaimedJob(
                    id: columnText(statement, at: 0),
                    type: columnText(statement, at: 1),
                    attempts: Int(columnInt64(statement, at: 2)) + 1,
                    maxAttempts: Int(columnInt64(statement, at: 3)),
                    fragmentID: columnOptionalText(statement, at: 4).flatMap(UUID.init(uuidString:)),
                    assetID: columnOptionalText(statement, at: 5).flatMap(UUID.init(uuidString:)),
                    assetPath: columnOptionalText(statement, at: 6)
                )
            }
        )
        guard let job = rows?.first else { return nil }

        do {
            try database.write(
                """
                UPDATE jobs
                SET status = 'running', attempts = ?, started_at = ?, updated_at = ?
                WHERE id = ?;
                """,
                bind: { statement in
                    bindInt64(Int64(job.attempts), to: statement, at: 1)
                    bindText(now, to: statement, at: 2)
                    bindText(now, to: statement, at: 3)
                    bindText(job.id, to: statement, at: 4)
                }
            )
        } catch {
            return nil
        }
        return job
    }

    private func complete(_ job: ClaimedJob, status: JobStatus, error: String?) throws {
        let now = Date()
        let retryDelay = TimeInterval(pow(2, Double(job.attempts)) * 5)
        let availableAt = status == .pending ? now.addingTimeInterval(retryDelay) : now
        try database.write(
            """
            UPDATE jobs
            SET status = ?, finished_at = ?, updated_at = ?, available_at = ?, last_error = ?
            WHERE id = ?;
            """,
            bind: { statement in
                bindText(status.rawValue, to: statement, at: 1)
                bindText(status == .pending ? nil : DateFormatting.string(from: now), to: statement, at: 2)
                bindText(DateFormatting.string(from: now), to: statement, at: 3)
                bindText(DateFormatting.string(from: availableAt), to: statement, at: 4)
                bindText(error, to: statement, at: 5)
                bindText(job.id, to: statement, at: 6)
            }
        )
    }

    private func insertExtraction(kind: String, text: String, job: ClaimedJob) throws {
        guard let fragmentID = job.fragmentID else { return }
        try database.write(
            """
            INSERT INTO extractions (id, fragment_id, asset_id, kind, content_text, metadata_json, created_at)
            VALUES (?, ?, ?, ?, ?, '{}', ?);
            """,
            bind: { statement in
                bindText(UUID().uuidString, to: statement, at: 1)
                bindText(fragmentID.uuidString, to: statement, at: 2)
                bindText(job.assetID?.uuidString, to: statement, at: 3)
                bindText(kind, to: statement, at: 4)
                bindText(text, to: statement, at: 5)
                bindText(DateFormatting.string(from: Date()), to: statement, at: 6)
            }
        )
    }

    private func updateFragmentStatus(for fragmentID: FragmentID?) {
        guard let fragmentID else { return }
        let placeholders = Self.handledTypes.map { _ in "?" }.joined(separator: ", ")
        let counts = try? database.query(
            """
            SELECT
              SUM(CASE WHEN status IN ('pending', 'running') THEN 1 ELSE 0 END),
              SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END)
            FROM jobs WHERE fragment_id = ? AND type IN (\(placeholders));
            """,
            bind: { statement in
                bindText(fragmentID.uuidString, to: statement, at: 1)
                for (index, type) in Self.handledTypes.enumerated() {
                    bindText(type, to: statement, at: Int32(index + 2))
                }
            },
            map: { (columnInt64($0, at: 0), columnInt64($0, at: 1)) }
        ).first
        guard let counts else { return }

        let newStatus: FragmentStatus
        if counts.0 > 0 {
            newStatus = .processing
        } else if counts.1 > 0 {
            newStatus = .failed
        } else {
            newStatus = .ready
        }
        try? database.write(
            "UPDATE fragments SET status = ?, updated_at = ? WHERE id = ?;",
            bind: { statement in
                bindText(newStatus.rawValue, to: statement, at: 1)
                bindText(DateFormatting.string(from: Date()), to: statement, at: 2)
                bindText(fragmentID.uuidString, to: statement, at: 3)
            }
        )
    }

    private func resetStaleRunningJobs() {
        try? database.write(
            "UPDATE jobs SET status = 'pending', updated_at = ? WHERE status = 'running';",
            bind: { bindText(DateFormatting.string(from: Date()), to: $0, at: 1) }
        )
    }
}
