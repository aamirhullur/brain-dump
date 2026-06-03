import SwiftUI

struct ContentView: View {
    @Bindable var appStore: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(fragmentStore: appStore.fragmentStore)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if let fragment = appStore.fragmentStore.selectedFragment {
                FragmentDetailView(fragment: fragment, fragmentStore: appStore.fragmentStore)
            } else {
                ContentUnavailableView("No Fragments", systemImage: "tray", description: Text("Use Option-Space to capture a text fragment or URL."))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem {
                Button {
                    appStore.showCapturePalette()
                } label: {
                    Label("Capture", systemImage: "plus")
                }
                .help("Capture Fragment")
            }
        }
        .alert("Startup Error", isPresented: Binding(
            get: { appStore.startupError != nil },
            set: { if !$0 { appStore.startupError = nil } }
        )) {
            Button("OK") { appStore.startupError = nil }
        } message: {
            Text(appStore.startupError ?? "")
        }
    }
}
