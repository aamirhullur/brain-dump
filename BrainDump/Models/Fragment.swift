import Foundation

struct Fragment: Identifiable, Equatable {
    let id: FragmentID
    let createdAt: Date
    let updatedAt: Date
    let sourceType: SourceType
    let title: String?
    let userNote: String?
    let annotation: String?
    let status: FragmentStatus
    let primaryAssetID: AssetID?
    let bookmarkedAt: Date?

    var isBookmarked: Bool {
        bookmarkedAt != nil
    }

    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return formattedTitle(title)
        }

        if let userNote, !userNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return formattedTitle(userNote)
        }

        switch sourceType {
        case .url:
            return "Untitled URL"
        case .screenshot:
            return "Untitled Screenshot"
        case .image:
            return "Untitled Image"
        case .text:
            return "Untitled Text"
        }
    }

    var previewText: String {
        let value = userNote ?? title ?? ""
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "No captured text yet" : String(collapsed.prefix(140))
    }

    var sourceLabel: String {
        switch sourceType {
        case .text:
            return "Text"
        case .url:
            return "URL"
        case .screenshot:
            return "Screenshot"
        case .image:
            return "Image"
        }
    }

    var sourceSystemImage: String {
        switch sourceType {
        case .text:
            return "text.alignleft"
        case .url:
            return "link"
        case .screenshot:
            return "viewfinder"
        case .image:
            return "photo"
        }
    }

    private func formattedTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if sourceType == .url, let url = URLDetector.url(from: trimmed), let host = url.host {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.isEmpty {
                return host
            }
            return "\(host)/\(path)"
        }
        return String(trimmed.prefix(80))
    }
}
