import SwiftUI

struct SidebarView: View {
    @Binding var selectedSection: AppSection
    let fragments: [Fragment]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarTitle()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SidebarSection("Inbox") {
                        sidebarItem(for: .allEvidence)
                        sidebarItem(for: .today)
                        sidebarItem(for: .unprocessed)
                        sidebarItem(for: .bookmarks)
                    }

                    SidebarSection("Sources") {
                        sidebarItem(for: .text)
                        sidebarItem(for: .links)
                        sidebarItem(for: .screenshots)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background {
            DesignTokens.primaryPurple
            .ignoresSafeArea()
        }
        .navigationTitle("Brain Dump")
    }

    private func sidebarItem(for section: AppSection) -> some View {
        SidebarItem(
            section: section,
            count: fragments.filter { section.includes($0) }.count,
            selectedSection: $selectedSection
        )
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.34))
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            content
        }
    }
}

private struct SidebarTitle: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .accessibilityHidden(true)
            Text("Brain Dump")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
}

private struct SidebarItem: View {
    let section: AppSection
    let count: Int
    @Binding var selectedSection: AppSection

    private var isSelected: Bool {
        section == selectedSection
    }

    var body: some View {
        Button {
            selectedSection = section
        } label: {
            HStack {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .white.opacity(0.6))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(section.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.78))
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.72) : .white.opacity(0.48))
                        .monospacedDigit()
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(DesignTokens.primaryPurple)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        count > 0 ? "\(section.title), \(count) fragments" : section.title
    }
}
