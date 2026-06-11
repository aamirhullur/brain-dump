import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum TimelineFocus: Hashable {
    case search
    case list
}

@MainActor
struct EvidenceTimelineView: View {
    @Bindable var fragmentStore: FragmentStore
    let section: AppSection
    @Binding var searchText: String
    @FocusState private var focus: TimelineFocus?

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredFragments: [Fragment] {
        let sectionFragments = fragmentStore.fragments.filter { section.includes($0) }
        let query = trimmedQuery
        guard !query.isEmpty else { return sectionFragments }
        return sectionFragments.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.previewText.localizedCaseInsensitiveContains(query)
                || $0.sourceLabel.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TimelineHeader(searchText: $searchText, focus: $focus)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if filteredFragments.isEmpty {
                            TimelineEmptyState(section: section, searchQuery: trimmedQuery)
                        } else {
                            Text(section.title)
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
                                    focus = .list
                                }
                                .contextMenu {
                                    Button {
                                        fragmentStore.toggleBookmark(fragment.id)
                                    } label: {
                                        Label(
                                            fragment.isBookmarked ? "Remove Bookmark" : "Bookmark",
                                            systemImage: fragment.isBookmarked ? "bookmark.slash" : "bookmark"
                                        )
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        delete(fragment)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .id(fragment.id)
                                Divider()
                                    .padding(.leading, 84)
                            }
                        }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focus, equals: .list)
                .onMoveCommand(perform: moveSelection)
                .onDeleteCommand(perform: deleteSelected)
                .onChange(of: fragmentStore.selectedFragmentID) { _, newValue in
                    if let newValue {
                        proxy.scrollTo(newValue)
                    }
                }
            }
        }
        .background(DesignTokens.contentBackground)
        .clipShape(TopLeadingRoundedRectangle(radius: 18))
        .background {
            Button("Focus Search") {
                focus = .search
            }
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onAppear {
            fragmentStore.loadFragments()
            focus = .list
        }
        .onChange(of: section) {
            ensureSelectionIsVisible()
        }
        .onChange(of: fragmentStore.fragments) {
            ensureSelectionIsVisible()
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

    private func ensureSelectionIsVisible() {
        let visible = filteredFragments
        if !visible.contains(where: { $0.id == fragmentStore.selectedFragmentID }) {
            fragmentStore.selectedFragmentID = visible.first?.id
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let visible = filteredFragments
        guard !visible.isEmpty else { return }
        guard let currentIndex = visible.firstIndex(where: { $0.id == fragmentStore.selectedFragmentID }) else {
            fragmentStore.selectedFragmentID = visible.first?.id
            return
        }

        switch direction {
        case .up:
            fragmentStore.selectedFragmentID = visible[max(0, currentIndex - 1)].id
        case .down:
            fragmentStore.selectedFragmentID = visible[min(visible.count - 1, currentIndex + 1)].id
        default:
            break
        }
    }

    private func deleteSelected() {
        guard let selected = fragmentStore.selectedFragment else { return }
        delete(selected)
    }

    private func delete(_ fragment: Fragment) {
        var nextSelectionID: FragmentID?
        if fragment.id == fragmentStore.selectedFragmentID {
            let visible = filteredFragments
            if let index = visible.firstIndex(where: { $0.id == fragment.id }) {
                if index + 1 < visible.count {
                    nextSelectionID = visible[index + 1].id
                } else if index > 0 {
                    nextSelectionID = visible[index - 1].id
                }
            }
        }

        fragmentStore.softDelete(fragment.id)

        if let nextSelectionID {
            fragmentStore.selectedFragmentID = nextSelectionID
        }
    }
}

private struct TimelineHeader: View {
    @Binding var searchText: String
    var focus: FocusState<TimelineFocus?>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search evidence...", text: $searchText)
                .textFieldStyle(.plain)
                .focused(focus, equals: .search)
                .onExitCommand {
                    focus.wrappedValue = .list
                }
                .accessibilityLabel("Search evidence")
            Text("⌘K")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
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
                        if fragment.isBookmarked {
                            Image(systemName: "bookmark.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
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
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = [fragment.displayTitle, fragment.sourceLabel]
        if fragment.isBookmarked {
            parts.append("Bookmarked")
        }
        parts.append(fragment.status.rawValue.capitalized)
        parts.append(fragment.createdAt.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: ", ")
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
        .accessibilityHidden(true)
    }
}

private struct TimelineEmptyState: View {
    let section: AppSection
    let searchQuery: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: searchQuery.isEmpty ? section.systemImage : "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.horizontal, 24)
    }

    private var title: String {
        guard searchQuery.isEmpty else { return "No results" }

        switch section {
        case .allEvidence:
            return "No evidence yet"
        case .today:
            return "Nothing captured today"
        case .unprocessed:
            return "Nothing to process"
        case .bookmarks:
            return "No bookmarks yet"
        case .text:
            return "No text fragments"
        case .links:
            return "No links yet"
        case .screenshots:
            return "No screenshots yet"
        }
    }

    private var message: String {
        guard searchQuery.isEmpty else {
            return "Nothing in \(section.title) matches \u{201C}\(searchQuery)\u{201D}."
        }

        switch section {
        case .allEvidence:
            return "Use the Memory Inlet to capture a fragment."
        case .today:
            return "Evidence you capture today will appear here."
        case .unprocessed:
            return "There is no pending evidence to process."
        case .bookmarks:
            return "Bookmarked fragments will appear here."
        case .text:
            return "Text you capture will appear here."
        case .links:
            return "Links you capture will appear here."
        case .screenshots:
            return "Screenshots you capture will appear here."
        }
    }
}
