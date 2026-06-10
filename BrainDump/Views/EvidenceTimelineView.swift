import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct EvidenceTimelineView: View {
    @Bindable var fragmentStore: FragmentStore
    @Binding var searchText: String

    private var filteredFragments: [Fragment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return fragmentStore.fragments }
        return fragmentStore.fragments.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.previewText.localizedCaseInsensitiveContains(query)
                || $0.sourceLabel.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TimelineHeader(searchText: $searchText)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filteredFragments.isEmpty {
                        TimelineEmptyState()
                    } else {
                        Text("Today")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 8)

                        ForEach(filteredFragments) { fragment in
                            EvidenceRow(
                                fragment: fragment,
                                thumbnailURL: fragmentStore.thumbnailURL(for: fragment),
                                isSelected: fragment.id == fragmentStore.selectedFragmentID
                            ) {
                                fragmentStore.select(fragment)
                            }
                            Divider()
                                .padding(.leading, 84)
                        }
                    }
                }
            }
        }
        .background(DesignTokens.contentBackground)
        .clipShape(TopLeadingRoundedRectangle(radius: 18))
        .onAppear {
            fragmentStore.loadFragments()
        }
        .onDrop(of: [.fileURL, .image, .png, .tiff], isTargeted: nil) { providers in
            Task { @MainActor in
                let images = await ImageIngest.images(from: providers)
                for image in images {
                    _ = try? fragmentStore.captureImage(
                        image.data,
                        sourceType: .image,
                        originalFilename: image.originalFilename,
                        mimeType: image.mimeType,
                        fileExtension: image.fileExtension
                    )
                }
            }
            return true
        }
    }
}

private struct TimelineHeader: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search evidence...", text: $searchText)
                .textFieldStyle(.plain)
            Text("⌘K")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(DesignTokens.contentSurface, in: RoundedRectangle(cornerRadius: 12))
        .padding(14)
    }
}

private struct EvidenceRow: View {
    let fragment: Fragment
    let thumbnailURL: URL?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 14) {
                Text(fragment.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(fragment.displayTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        SourceTag(fragment.sourceLabel.uppercased())
                    }

                    Text(fragment.previewText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                SourceThumbnail(fragment: fragment, thumbnailURL: thumbnailURL)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignTokens.primaryPurple.opacity(0.88))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 120 / 255, green: 97 / 255, blue: 225 / 255).opacity(0.55), lineWidth: 1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
            }
        }
        .buttonStyle(.plain)
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
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct SourceThumbnail: View {
    let fragment: Fragment
    let thumbnailURL: URL?

    var body: some View {
        ZStack {
            if let thumbnailURL, let image = ImageCache.image(at: thumbnailURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                Image(systemName: fragment.sourceSystemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
    }
}

private struct TimelineEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No evidence yet")
                .font(.callout.weight(.medium))
            Text("Use the Memory Inlet to capture a fragment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }
}
