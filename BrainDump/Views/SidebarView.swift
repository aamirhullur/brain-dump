import SwiftUI

struct SidebarView: View {
    @Binding var selectedSection: AppSection
    let fragmentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarTitle()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SidebarSection("Inbox") {
                        SidebarItem(section: .allEvidence, count: fragmentCount, selectedSection: $selectedSection)
                        SidebarItem(section: .today, count: todayCount, selectedSection: $selectedSection)
                        SidebarItem(section: .unprocessed, count: fragmentCount, selectedSection: $selectedSection)
                        SidebarItem(section: .bookmarks, count: 0, selectedSection: $selectedSection)
                    }

                    SidebarSection("Sources") {
                        SidebarItem(section: .text, count: textCount, selectedSection: $selectedSection)
                        SidebarItem(section: .links, count: linkCount, selectedSection: $selectedSection)
                        SidebarItem(section: .screenshots, count: 0, selectedSection: $selectedSection)
                        SidebarItem(section: .quickNotes, count: 0, selectedSection: $selectedSection)
                        SidebarItem(section: .files, count: 0, selectedSection: $selectedSection)
                    }

                    SidebarSection("Insights") {
                        SidebarItem(section: .themes, count: 0, selectedSection: $selectedSection)
                        SidebarItem(section: .digests, count: 0, selectedSection: $selectedSection)
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

    private var todayCount: Int { fragmentCount }
    private var textCount: Int { fragmentCount }
    private var linkCount: Int { 0 }
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
    }
}
