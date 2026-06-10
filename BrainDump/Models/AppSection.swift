import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case allEvidence
    case today
    case unprocessed
    case bookmarks
    case text
    case links
    case screenshots

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
        }
    }

    func includes(_ fragment: Fragment, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .allEvidence:
            return true
        case .today:
            return calendar.isDate(fragment.createdAt, inSameDayAs: now)
        case .unprocessed:
            return fragment.status == .captured || fragment.status == .processing
        case .bookmarks:
            return fragment.isBookmarked
        case .text:
            return fragment.sourceType == .text
        case .links:
            return fragment.sourceType == .url
        case .screenshots:
            return fragment.sourceType == .screenshot
        }
    }
}
