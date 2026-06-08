import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case allEvidence
    case today
    case unprocessed
    case bookmarks
    case text
    case links
    case screenshots
    case quickNotes
    case files
    case themes
    case digests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allEvidence:
            return "All Evidence"
        case .today:
            return "Today"
        case .unprocessed:
            return "Unprocessed"
        case .bookmarks:
            return "Bookmarks"
        case .text:
            return "Text"
        case .links:
            return "Links"
        case .screenshots:
            return "Screenshots"
        case .quickNotes:
            return "Quick Notes"
        case .files:
            return "Files"
        case .themes:
            return "Themes"
        case .digests:
            return "Digests"
        }
    }

    var systemImage: String {
        switch self {
        case .allEvidence:
            return "doc.text.magnifyingglass"
        case .today:
            return "clock"
        case .unprocessed:
            return "tray.and.arrow.down"
        case .bookmarks:
            return "bookmark"
        case .text:
            return "text.alignleft"
        case .links:
            return "link"
        case .screenshots:
            return "viewfinder"
        case .quickNotes:
            return "square.and.pencil"
        case .files:
            return "doc"
        case .themes:
            return "sparkles"
        case .digests:
            return "newspaper"
        }
    }
}
