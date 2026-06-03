import AppKit
import SwiftUI

@MainActor
final class CapturePaletteController {
    private var panel: NSPanel?
    private let appStore: AppStore

    init(appStore: AppStore) {
        self.appStore = appStore
    }

    func show() {
        if panel == nil {
            let rootView = CapturePaletteView(
                fragmentStore: appStore.fragmentStore,
                onClose: { [weak self] in self?.hide() }
            )
            let hostingController = NSHostingController(rootView: rootView)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 168),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "Capture"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = hostingController
            self.panel = panel
        }

        guard let panel else { return }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        appStore.hideCapturePalette()
    }
}
