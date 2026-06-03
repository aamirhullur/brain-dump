import SwiftUI

struct InboxView: View {
    @Bindable var fragmentStore: FragmentStore

    var body: some View {
        SidebarView(fragmentStore: fragmentStore)
    }
}
