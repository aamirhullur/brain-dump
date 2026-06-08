import SwiftUI

struct InboxView: View {
    @Bindable var fragmentStore: FragmentStore
    @State private var selectedSection: AppSection = .allEvidence

    var body: some View {
        SidebarView(
            selectedSection: $selectedSection,
            fragmentCount: fragmentStore.fragments.count
        )
    }
}
