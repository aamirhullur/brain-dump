import Foundation

struct Fragment: Identifiable, Equatable {
    let id: FragmentID
    let createdAt: Date
    let updatedAt: Date
    let sourceType: SourceType
    let title: String?
    let userNote: String?
    let status: FragmentStatus
    let primaryAssetID: AssetID?

    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return formattedTitle(title)
        }

        if let userNote, !userNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return formattedTitle(userNote)
        }

        return sourceType == .url ? "Untitled URL" : "Untitled Text"
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
