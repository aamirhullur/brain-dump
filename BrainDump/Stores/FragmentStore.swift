import Foundation
import Observation

enum CaptureError: LocalizedError {
    case emptyImageData
    case unsupportedSourceType

    var errorDescription: String? {
        switch self {
        case .emptyImageData:
            return "The image was empty."
        case .unsupportedSourceType:
            return "This source type cannot be captured as an image."
        }
    }
}

@Observable
@MainActor
final class FragmentStore {
    private let database: Database
    private let blobStore: BlobStore
    var thumbnailsRoot: URL?
    var onJobsEnqueued: (() -> Void)?

    private(set) var fragments: [Fragment] = []
    var selectedFragmentID: FragmentID?
    private(set) var lastError: String?

    init(database: Database, blobStore: BlobStore) {
        self.database = database
        self.blobStore = blobStore
    }

    var selectedFragment: Fragment? {
        fragments.first { $0.id == selectedFragmentID }
    }

    func loadFragments() {
        do {
            fragments = try database.query(
                """
                SELECT id, created_at, updated_at, source_type, title, user_note, status, primary_asset_id
                FROM fragments
                WHERE deleted_at IS NULL
                ORDER BY created_at DESC;
                """
            ) { statement in
                Fragment(
                    id: UUID(uuidString: columnText(statement, at: 0)) ?? UUID(),
                    createdAt: DateFormatting.date(from: columnText(statement, at: 1)),
                    updatedAt: DateFormatting.date(from: columnText(statement, at: 2)),
                    sourceType: SourceType(rawValue: columnText(statement, at: 3)) ?? .text,
                    title: columnOptionalText(statement, at: 4),
                    userNote: columnOptionalText(statement, at: 5),
                    status: FragmentStatus(rawValue: columnText(statement, at: 6)) ?? .captured,
                    primaryAssetID: columnOptionalText(statement, at: 7).flatMap(UUID.init(uuidString:))
                )
            }

            if selectedFragmentID == nil {
                selectedFragmentID = fragments.first?.id
            } else if let selectedFragmentID, !fragments.contains(where: { $0.id == selectedFragmentID }) {
                self.selectedFragmentID = fragments.first?.id
            }

            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func select(_ fragment: Fragment?) {
        selectedFragmentID = fragment?.id
    }

    func capture(rawInput: String) throws {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sourceType: SourceType = URLDetector.url(from: trimmed) == nil ? .text : .url
        let now = Date()
        let fragmentID = UUID()
        let assetID = UUID()
        let data = Data(trimmed.utf8)
        let assetRecord = try blobStore.writeTextAsset(data, fragmentID: fragmentID, assetID: assetID)
        let sourceURL = sourceType == .url ? URLDetector.url(from: trimmed)?.absoluteString : nil
        let title = sourceType == .url ? sourceURL : String(trimmed.prefix(80))

        try database.execute("BEGIN TRANSACTION;")
        do {
            try database.write(
                """
                INSERT INTO fragments (id, created_at, updated_at, source_type, title, user_note, status, primary_asset_id, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL);
                """,
                bind: { statement in
                    bindText(fragmentID.uuidString, to: statement, at: 1)
                    bindText(DateFormatting.string(from: now), to: statement, at: 2)
                    bindText(DateFormatting.string(from: now), to: statement, at: 3)
                    bindText(sourceType.rawValue, to: statement, at: 4)
                    bindText(title, to: statement, at: 5)
                    bindText(trimmed, to: statement, at: 6)
                    bindText(FragmentStatus.captured.rawValue, to: statement, at: 7)
                }
            )

            try database.write(
                """
                INSERT INTO assets (id, fragment_id, kind, sha256, original_filename, mime_type, byte_size, local_path, source_url, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bind: { statement in
                    bindText(assetID.uuidString, to: statement, at: 1)
                    bindText(fragmentID.uuidString, to: statement, at: 2)
                    bindText(sourceType == .url ? AssetKind.url.rawValue : AssetKind.text.rawValue, to: statement, at: 3)
                    bindText(assetRecord.sha256, to: statement, at: 4)
                    bindText(assetRecord.fileURL.lastPathComponent, to: statement, at: 5)
                    bindText("text/plain; charset=utf-8", to: statement, at: 6)
                    bindInt64(Int64(data.count), to: statement, at: 7)
                    bindText(assetRecord.fileURL.path, to: statement, at: 8)
                    bindText(sourceURL, to: statement, at: 9)
                    bindText(DateFormatting.string(from: now), to: statement, at: 10)
                }
            )

            try database.write(
                "UPDATE fragments SET primary_asset_id = ?, updated_at = ? WHERE id = ?;",
                bind: { statement in
                    bindText(assetID.uuidString, to: statement, at: 1)
                    bindText(DateFormatting.string(from: now), to: statement, at: 2)
                    bindText(fragmentID.uuidString, to: statement, at: 3)
                }
            )

            try enqueueJob(type: sourceType == .url ? "extract_url_metadata" : "index_text_fragment", fragmentID: fragmentID, assetID: assetID, now: now)
            try enqueueJob(type: "prepare_fragment_card", fragmentID: fragmentID, assetID: assetID, now: now)

            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            try? FileManager.default.removeItem(at: assetRecord.fileURL)
            throw error
        }

        loadFragments()
        selectedFragmentID = fragmentID
        onJobsEnqueued?()
    }

    @discardableResult
    func captureImage(
        _ data: Data,
        sourceType: SourceType,
        originalFilename: String? = nil,
        mimeType: String = "image/png",
        fileExtension: String = "png",
        capturedAt: Date = Date()
    ) throws -> FragmentID {
        guard !data.isEmpty else { throw CaptureError.emptyImageData }
        guard sourceType == .screenshot || sourceType == .image else { throw CaptureError.unsupportedSourceType }

        let fragmentID = UUID()
        let assetID = UUID()
        let assetRecord = try blobStore.writeAsset(data, fragmentID: fragmentID, assetID: assetID, fileExtension: fileExtension)
        let title = originalFilename ?? defaultImageTitle(sourceType: sourceType, capturedAt: capturedAt)

        try database.execute("BEGIN TRANSACTION;")
        do {
            try database.write(
                """
                INSERT INTO fragments (id, created_at, updated_at, source_type, title, user_note, status, primary_asset_id, deleted_at)
                VALUES (?, ?, ?, ?, ?, NULL, ?, NULL, NULL);
                """,
                bind: { statement in
                    bindText(fragmentID.uuidString, to: statement, at: 1)
                    bindText(DateFormatting.string(from: capturedAt), to: statement, at: 2)
                    bindText(DateFormatting.string(from: capturedAt), to: statement, at: 3)
                    bindText(sourceType.rawValue, to: statement, at: 4)
                    bindText(title, to: statement, at: 5)
                    bindText(FragmentStatus.captured.rawValue, to: statement, at: 6)
                }
            )

            try database.write(
                """
                INSERT INTO assets (id, fragment_id, kind, sha256, original_filename, mime_type, byte_size, local_path, source_url, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?);
                """,
                bind: { statement in
                    bindText(assetID.uuidString, to: statement, at: 1)
                    bindText(fragmentID.uuidString, to: statement, at: 2)
                    bindText(AssetKind.image.rawValue, to: statement, at: 3)
                    bindText(assetRecord.sha256, to: statement, at: 4)
                    bindText(originalFilename ?? assetRecord.fileURL.lastPathComponent, to: statement, at: 5)
                    bindText(mimeType, to: statement, at: 6)
                    bindInt64(Int64(data.count), to: statement, at: 7)
                    bindText(assetRecord.fileURL.path, to: statement, at: 8)
                    bindText(DateFormatting.string(from: capturedAt), to: statement, at: 9)
                }
            )

            try database.write(
                "UPDATE fragments SET primary_asset_id = ? WHERE id = ?;",
                bind: { statement in
                    bindText(assetID.uuidString, to: statement, at: 1)
                    bindText(fragmentID.uuidString, to: statement, at: 2)
                }
            )

            try enqueueJob(type: "generate_thumbnail", fragmentID: fragmentID, assetID: assetID, now: capturedAt)
            try enqueueJob(type: "ocr_image", fragmentID: fragmentID, assetID: assetID, now: capturedAt)
            try enqueueJob(type: "prepare_fragment_card", fragmentID: fragmentID, assetID: assetID, now: capturedAt)

            try database.execute("COMMIT;")
        } catch {
            try? database.execute("ROLLBACK;")
            try? FileManager.default.removeItem(at: assetRecord.fileURL)
            throw error
        }

        loadFragments()
        selectedFragmentID = fragmentID
        onJobsEnqueued?()
        return fragmentID
    }

    func primaryAssetLocalPath(for fragmentID: FragmentID) -> String? {
        let rows = try? database.query(
            """
            SELECT a.local_path
            FROM fragments f
            JOIN assets a ON a.id = f.primary_asset_id
            WHERE f.id = ?;
            """,
            bind: { bindText(fragmentID.uuidString, to: $0, at: 1) },
            map: { columnOptionalText($0, at: 0) }
        )
        return rows?.first ?? nil
    }

    private func defaultImageTitle(sourceType: SourceType, capturedAt: Date) -> String {
        let stamp = capturedAt.formatted(date: .abbreviated, time: .shortened)
        return sourceType == .screenshot ? "Screenshot \(stamp)" : "Image \(stamp)"
    }

    func thumbnailURL(for fragment: Fragment) -> URL? {
        guard let thumbnailsRoot, let assetID = fragment.primaryAssetID else { return nil }
        let url = thumbnailsRoot.appendingPathComponent("\(assetID.uuidString).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func extractedText(for fragmentID: FragmentID) -> String? {
        let rows = try? database.query(
            "SELECT content_text FROM extractions WHERE fragment_id = ? AND kind = 'ocr_text' ORDER BY created_at DESC LIMIT 1;",
            bind: { bindText(fragmentID.uuidString, to: $0, at: 1) },
            map: { columnOptionalText($0, at: 0) }
        )
        let text = rows?.first ?? nil
        return text?.isEmpty == false ? text : nil
    }

    func pendingJobCount(for fragmentID: FragmentID) -> Int {
        let placeholders = JobRunner.handledTypes.map { _ in "?" }.joined(separator: ", ")
        let rows = try? database.query(
            "SELECT COUNT(*) FROM jobs WHERE fragment_id = ? AND status IN ('pending', 'running') AND type IN (\(placeholders));",
            bind: { statement in
                bindText(fragmentID.uuidString, to: statement, at: 1)
                for (index, type) in JobRunner.handledTypes.enumerated() {
                    bindText(type, to: statement, at: Int32(index + 2))
                }
            },
            map: { Int(columnInt64($0, at: 0)) }
        )
        return rows?.first ?? 0
    }

    func jobCount(for fragmentID: FragmentID) -> Int {
        let rows = try? database.query(
            "SELECT COUNT(*) FROM jobs WHERE fragment_id = ?;",
            bind: { bindText(fragmentID.uuidString, to: $0, at: 1) },
            map: { Int(columnInt64($0, at: 0)) }
        )
        return rows?.first ?? 0
    }

    private func enqueueJob(type: String, fragmentID: FragmentID, assetID: AssetID, now: Date) throws {
        try database.write(
            """
            INSERT INTO jobs (id, created_at, updated_at, type, status, attempts, max_attempts, available_at, fragment_id, asset_id, payload_json)
            VALUES (?, ?, ?, ?, ?, 0, 3, ?, ?, ?, ?);
            """,
            bind: { statement in
                bindText(UUID().uuidString, to: statement, at: 1)
                bindText(DateFormatting.string(from: now), to: statement, at: 2)
                bindText(DateFormatting.string(from: now), to: statement, at: 3)
                bindText(type, to: statement, at: 4)
                bindText(JobStatus.pending.rawValue, to: statement, at: 5)
                bindText(DateFormatting.string(from: now), to: statement, at: 6)
                bindText(fragmentID.uuidString, to: statement, at: 7)
                bindText(assetID.uuidString, to: statement, at: 8)
                bindText("{}", to: statement, at: 9)
            }
        )
    }
}
