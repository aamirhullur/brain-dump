import AppKit
import SwiftUI

struct FragmentDetailView: View {
    let fragment: Fragment
    let fragmentStore: FragmentStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                DetailHeader(fragment: fragment)

                EvidenceBlock(
                    fragment: fragment,
                    assetPath: fragmentStore.primaryAssetLocalPath(for: fragment.id)
                )

                if let extractedText = fragmentStore.extractedText(for: fragment.id) {
                    ExtractedTextBlock(text: extractedText)
                }

                InterpretationBlock(
                    status: fragment.status,
                    pendingJobCount: fragmentStore.pendingJobCount(for: fragment.id)
                )

                ThemeBlock()

                ConnectedEvidenceBlock()
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 38)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(fragment.displayTitle)
        .background(DesignTokens.contentBackground)
    }
}

private struct DetailHeader: View {
    let fragment: Fragment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SourceTag(fragment.sourceLabel.uppercased())
                Spacer()
                StatusBadge(status: fragment.status)
            }

            Text(fragment.displayTitle)
                .font(.title2.weight(.semibold))
                .lineLimit(3)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 4) {
                Text(fragment.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(fragment.sourceType == .url ? "Captured from web" : "Captured from Brain Dump")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

private struct EvidenceBlock: View {
    let fragment: Fragment
    let assetPath: String?

    private var isImageFragment: Bool {
        fragment.sourceType == .screenshot || fragment.sourceType == .image
    }

    var body: some View {
        InspectorSection("Original evidence") {
            if isImageFragment {
                if let assetPath, let image = NSImage(contentsOfFile: assetPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 420)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.quaternary)
                        }
                } else {
                    Label("Image evidence is missing from local storage.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(DesignTokens.contentSurface, in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Text(fragment.userNote ?? "")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(DesignTokens.contentSurface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct ExtractedTextBlock: View {
    let text: String

    var body: some View {
        InspectorSection("Extracted text") {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(DesignTokens.contentSurface, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct InterpretationBlock: View {
    let status: FragmentStatus
    let pendingJobCount: Int

    var body: some View {
        InspectorSection("Interpretation") {
            VStack(alignment: .leading, spacing: 10) {
                Text("This fragment is saved as raw evidence. Summary, concepts, and related themes will appear after AI interpretation runs.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if pendingJobCount > 0 {
                    Label("\(pendingJobCount) background jobs remaining", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Label(status == .failed ? "Processing failed" : "Processing complete", systemImage: status == .failed ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ThemeBlock: View {
    private let themes = ["Local-First", "Privacy", "Evidence Trail"]

    var body: some View {
        InspectorSection("Related themes") {
            HStack(spacing: 8) {
                ForEach(themes, id: \.self) { theme in
                    Text(theme)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DesignTokens.primaryPurple.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                }

                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(DesignTokens.contentSurface, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct ConnectedEvidenceBlock: View {
    var body: some View {
        InspectorSection("Connected evidence") {
            VStack(spacing: 0) {
                ConnectedEvidenceRow(title: "Offline reliability patterns", subtitle: "Future processing result")
                Divider()
                ConnectedEvidenceRow(title: "Capture without organization", subtitle: "Theme candidate")
            }
            .background(DesignTokens.contentSurface, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct ConnectedEvidenceRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
            content
        }
    }
}

private struct StatusBadge: View {
    let status: FragmentStatus

    var body: some View {
        Label(status.rawValue.capitalized, systemImage: symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(DesignTokens.contentSurface, in: Capsule())
    }

    private var symbolName: String {
        switch status {
        case .captured:
            return "checkmark.circle"
        case .processing:
            return "circle.dotted"
        case .ready:
            return "sparkle"
        case .failed:
            return "exclamationmark.circle"
        }
    }
}

private struct SourceTag: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(DesignTokens.contentSurface, in: RoundedRectangle(cornerRadius: 6))
    }
}
