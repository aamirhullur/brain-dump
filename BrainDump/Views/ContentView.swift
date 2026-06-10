import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var appStore: AppStore
    @State private var selectedSection: AppSection = .allEvidence
    @State private var searchText = ""
    @State private var isSidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarView(
                    selectedSection: $selectedSection,
                    fragmentCount: appStore.fragmentStore.fragments.count
                )
                .frame(width: 260)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            EvidenceTimelineView(
                fragmentStore: appStore.fragmentStore,
                searchText: $searchText
            )
            .frame(minWidth: 430, idealWidth: 500, maxWidth: 560)

            if let fragment = appStore.fragmentStore.selectedFragment {
                FragmentDetailView(fragment: fragment, fragmentStore: appStore.fragmentStore)
                    .frame(minWidth: 440, maxWidth: .infinity)
            } else {
                EmptyMemoryView {
                    appStore.showMemoryInlet()
                }
                .frame(minWidth: 440, maxWidth: .infinity)
            }
        }
        .background(DesignTokens.primaryPurple)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(DesignTokens.primaryPurple, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isSidebarVisible.toggle()
                    }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appStore.showMemoryInlet()
                } label: {
                    Label("Capture", systemImage: "plus")
                }
                .help("Capture Fragment")

                Button {
                } label: {
                    Label("Bookmark", systemImage: "bookmark")
                }
                .disabled(appStore.fragmentStore.selectedFragment == nil)
                .help("Bookmark")
            }
        }
        .alert(
            appStore.captureError?.title ?? "Capture Failed",
            isPresented: Binding(
                get: { appStore.captureError != nil },
                set: { if !$0 { appStore.captureError = nil } }
            ),
            presenting: appStore.captureError
        ) { failure in
            if failure.needsScreenRecordingPermission {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                    appStore.captureError = nil
                }
            }
            Button("OK", role: .cancel) { appStore.captureError = nil }
        } message: { failure in
            Text(failure.message)
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

private struct EmptyMemoryView: View {
    let onCapture: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 34, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 7) {
                Text("Start with evidence")
                    .font(.title3.weight(.semibold))
                Text("Capture a note, link, screenshot, or file. Brain Dump keeps the original evidence and interprets it later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                onCapture()
            } label: {
                Label("Open Memory Inlet", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
