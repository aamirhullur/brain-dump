import Foundation

enum CaptureIntent: String, CaseIterable, Identifiable {
    case text
    case url
    case screenshot
    case paste
    case quickNote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text:
            return "Text"
        case .url:
            return "URL"
        case .screenshot:
            return "Screenshot"
        case .paste:
            return "Paste"
        case .quickNote:
            return "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .url:
            return "link"
        case .screenshot:
            return "viewfinder"
        case .paste:
            return "doc.on.clipboard"
        case .quickNote:
            return "square.and.pencil"
        }
    }

    var prompt: String {
        switch self {
        case .text:
            return "Paste or type selected text"
        case .url:
            return "Paste a URL or page note"
        case .screenshot:
            return "Prepare region capture"
        case .paste:
            return "Save clipboard contents"
        case .quickNote:
            return "Write a quick note"
        }
    }
}
