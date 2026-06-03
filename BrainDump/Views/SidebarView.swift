import SwiftUI

struct SidebarView: View {
    @Bindable var fragmentStore: FragmentStore

    var body: some View {
        List(selection: $fragmentStore.selectedFragmentID) {
            Section("Inbox") {
                ForEach(fragmentStore.fragments) { fragment in
                    FragmentRow(fragment: fragment)
                        .tag(fragment.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Brain Dump")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EmptyView()
            }
        }
        .onAppear {
            fragmentStore.loadFragments()
        }
        .overlay {
            if fragmentStore.fragments.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Inbox is empty")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct FragmentRow: View {
    let fragment: Fragment

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(fragment.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.body)
            }
        } icon: {
            Image(systemName: fragment.sourceType == .url ? "link" : "text.alignleft")
                .foregroundStyle(.secondary)
        }
    }
}
