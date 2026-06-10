import Foundation
import GRDB
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

extension Fragment {
    init(row: Row) {
        self.init(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            createdAt: DateFormatting.date(from: row["created_at"]),
            updatedAt: DateFormatting.date(from: row["updated_at"]),
            sourceType: SourceType(rawValue: row["source_type"]) ?? .text,
            title: row["title"],
            userNote: row["user_note"],
            status: FragmentStatus(rawValue: row["status"]) ?? .captured,
            primaryAssetID: (row["primary_asset_id"] as String?).flatMap(UUID.init(uuidString:)),
            bookmarkedAt: (row["bookmarked_at"] as String?).map(DateFormatting.date(from:))
        )
    }
}

@Observable
@MainActor
final class FragmentStore {
    private let database: AppDatabase
    private let blobStore: BlobStore
    var thumbnailsRoot: URL?
    var onJobsEnqueued: (() -> Void)?

    private(set) var fragments: [Fragment] = []
    private(set) var processingCount = 0
    var selectedFragmentID: FragmentID?
    private(set) var lastError: String?

    init(database: AppDatabase, blobStore: BlobStore) {
        self.database = database
        self.blobStore = blobStore
    }

    var selectedFragment: Fragment? {
        fragments.first { $0.id == selectedFragmentID }
    }

    func loadFragments() {
        do {
            fragments = try database.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, created_at, updated_at, source_type, title, user_note, status, primary_asset_id, bookmarked_at
                    FROM fragments
                    WHERE deleted_at IS NULL
                    ORDER BY created_at DESC
                    """
                ).map(Fragment.init(row:))
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

        refreshProcessingCount()
    }

    func refreshProcessingCount() {
        let count = try? database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM jobs
                WHERE status IN ('pending', 'running')
                  AND type IN (SELECT value FROM json_each(:types))
                """,
                arguments: ["types": JobRunner.handledTypesJSON]
            )
        }
        processingCount = count ?? 0
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

        do {
            try database.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO fragments (id, created_at, updated_at, source_type, title, user_note, status, primary_asset_id, deleted_at, bookmarked_at)
                    VALUES (:id, :now, :now, :source_type, :title, :user_note, :status, NULL, NULL, NULL)
                    """,
                    arguments: [
                        "id": fragmentID.uuidString,
                        "now": DateFormatting.string(from: now),
                        "source_type": sourceType.rawValue,
                        "title": title,
                        "user_note": trimmed,
                        "status": FragmentStatus.captured.rawValue
                    ]
                )

                try db.execute(
                    sql: """
                    INSERT INTO assets (id, fragment_id, kind, sha256, original_filename, mime_type, byte_size, local_path, source_url, created_at)
                    VALUES (:id, :fragment_id, :kind, :sha256, :original_filename, :mime_type, :byte_size, :local_path, :source_url, :created_at)
                    """,
                    arguments: [
                        "id": assetID.uuidString,
                        "fragment_id": fragmentID.uuidString,
                        "kind": sourceType == .url ? AssetKind.url.rawValue : AssetKind.text.rawValue,
                        "sha256": assetRecord.sha256,
                        "original_filename": assetRecord.fileURL.lastPathComponent,
                        "mime_type": "text/plain; charset=utf-8",
                        "byte_size": data.count,
                        "local_path": assetRecord.fileURL.path,
                        "source_url": sourceURL,
                        "created_at": DateFormatting.string(from: now)
                    ]
                )

                try db.execute(
                    sql: "UPDATE fragments SET primary_asset_id = :asset_id, updated_at = :now WHERE id = :id",
                    arguments: [
                        "asset_id": assetID.uuidString,
                        "now": DateFormatting.string(from: now),
                        "id": fragmentID.uuidString
                    ]
                )

                try Self.enqueueJob(db, type: sourceType == .url ? "extract_url_metadata" : "index_text_fragment", fragmentID: fragmentID, assetID: assetID, now: now)
                try Self.enqueueJob(db, type: "prepare_fragment_card", fragmentID: fragmentID, assetID: assetID, now: now)
            }
        } catch {
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

        do {
            try database.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO fragments (id, created_at, updated_at, source_type, title, user_note, status, primary_asset_id, deleted_at, bookmarked_at)
                    VALUES (:id, :now, :now, :source_type, :title, NULL, :status, NULL, NULL, NULL)
                    """,
                    arguments: [
                        "id": fragmentID.uuidString,
                        "now": DateFormatting.string(from: capturedAt),
                        "source_type": sourceType.rawValue,
                        "title": title,
                        "status": FragmentStatus.captured.rawValue
                    ]
                )

                try db.execute(
                    sql: """
                    INSERT INTO assets (id, fragment_id, kind, sha256, original_filename, mime_type, byte_size, local_path, source_url, created_at)
                    VALUES (:id, :fragment_id, :kind, :sha256, :original_filename, :mime_type, :byte_size, :local_path, NULL, :created_at)
                    """,
                    arguments: [
                        "id": assetID.uuidString,
                        "fragment_id": fragmentID.uuidString,
                        "kind": AssetKind.image.rawValue,
                        "sha256": assetRecord.sha256,
                        "original_filename": originalFilename ?? assetRecord.fileURL.lastPathComponent,
                        "mime_type": mimeType,
                        "byte_size": data.count,
                        "local_path": assetRecord.fileURL.path,
                        "created_at": DateFormatting.string(from: capturedAt)
                    ]
                )

                try db.execute(
                    sql: "UPDATE fragments SET primary_asset_id = :asset_id WHERE id = :id",
                    arguments: ["asset_id": assetID.uuidString, "id": fragmentID.uuidString]
                )

                try Self.enqueueJob(db, type: "generate_thumbnail", fragmentID: fragmentID, assetID: assetID, now: capturedAt)
                try Self.enqueueJob(db, type: "ocr_image", fragmentID: fragmentID, assetID: assetID, now: capturedAt)
                try Self.enqueueJob(db, type: "prepare_fragment_card", fragmentID: fragmentID, assetID: assetID, now: capturedAt)
            }
        } catch {
            try? FileManager.default.removeItem(at: assetRecord.fileURL)
            throw error
        }

        loadFragments()
        selectedFragmentID = fragmentID
        onJobsEnqueued?()
        return fragmentID
    }

    func softDelete(_ fragmentID: FragmentID) {
        do {
            let now = Date()
            try database.write { db in
                try db.execute(
                    sql: "UPDATE fragments SET deleted_at = :now, updated_at = :now WHERE id = :id AND deleted_at IS NULL",
                    arguments: ["now": DateFormatting.string(from: now), "id": fragmentID.uuidString]
                )
            }
        } catch {
            lastError = error.localizedDescription
            return
        }
        loadFragments()
    }

    func toggleBookmark(_ fragmentID: FragmentID) {
        guard let fragment = fragments.first(where: { $0.id == fragmentID }) else { return }
        let now = Date()
        let bookmarkedAt: Date? = fragment.isBookmarked ? nil : now
        do {
            try database.write { db in
                try db.execute(
                    sql: "UPDATE fragments SET bookmarked_at = :bookmarked_at, updated_at = :now WHERE id = :id",
                    arguments: [
                        "bookmarked_at": bookmarkedAt.map(DateFormatting.string(from:)),
                        "now": DateFormatting.string(from: now),
                        "id": fragmentID.uuidString
                    ]
                )
            }
        } catch {
            lastError = error.localizedDescription
            return
        }
        loadFragments()
    }

    func isBookmarked(_ fragmentID: FragmentID) -> Bool {
        fragments.first { $0.id == fragmentID }?.isBookmarked ?? false
    }

    func updateUserNote(_ note: String, for fragmentID: FragmentID) {
        let storedNote: String? = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        do {
            try database.write { db in
                try db.execute(
                    sql: "UPDATE fragments SET user_note = :note, updated_at = :now WHERE id = :id",
                    arguments: [
                        "note": storedNote,
                        "now": DateFormatting.string(from: Date()),
                        "id": fragmentID.uuidString
                    ]
                )
            }
        } catch {
            lastError = error.localizedDescription
            return
        }
        loadFragments()
    }

    func primaryAssetLocalPath(for fragmentID: FragmentID) -> String? {
        try? database.read { db in
            try String.fetchOne(
                db,
                sql: """
                SELECT a.local_path
                FROM fragments f
                JOIN assets a ON a.id = f.primary_asset_id
                WHERE f.id = :id
                """,
                arguments: ["id": fragmentID.uuidString]
            )
        }
    }

    func thumbnailURL(for fragment: Fragment) -> URL? {
        guard let thumbnailsRoot, let assetID = fragment.primaryAssetID else { return nil }
        let url = thumbnailsRoot.appendingPathComponent("\(assetID.uuidString).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func extractedText(for fragmentID: FragmentID) -> String? {
        let text = try? database.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT content_text FROM extractions WHERE fragment_id = :id AND kind = 'ocr_text' ORDER BY created_at DESC LIMIT 1",
                arguments: ["id": fragmentID.uuidString]
            )
        }
        return text?.isEmpty == false ? text : nil
    }

    func pendingJobCount(for fragmentID: FragmentID) -> Int {
        let count = try? database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM jobs
                WHERE fragment_id = :id AND status IN ('pending', 'running')
                  AND type IN (SELECT value FROM json_each(:types))
                """,
                arguments: ["id": fragmentID.uuidString, "types": JobRunner.handledTypesJSON]
            )
        }
        return count ?? 0
    }

    func jobCount(for fragmentID: FragmentID) -> Int {
        let count = try? database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM jobs WHERE fragment_id = :id",
                arguments: ["id": fragmentID.uuidString]
            )
        }
        return count ?? 0
    }

    private func defaultImageTitle(sourceType: SourceType, capturedAt: Date) -> String {
        let stamp = capturedAt.formatted(date: .abbreviated, time: .shortened)
        return sourceType == .screenshot ? "Screenshot \(stamp)" : "Image \(stamp)"
    }

    private static func enqueueJob(_ db: GRDB.Database, type: String, fragmentID: FragmentID, assetID: AssetID, now: Date) throws {
        try db.execute(
            sql: """
            INSERT INTO jobs (id, created_at, updated_at, type, status, attempts, max_attempts, available_at, fragment_id, asset_id, payload_json)
            VALUES (:id, :now, :now, :type, :status, 0, 3, :now, :fragment_id, :asset_id, '{}')
            """,
            arguments: [
                "id": UUID().uuidString,
                "now": DateFormatting.string(from: now),
                "type": type,
                "status": JobStatus.pending.rawValue,
                "fragment_id": fragmentID.uuidString,
                "asset_id": assetID.uuidString
            ]
        )
    }
}
