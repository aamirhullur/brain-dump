import AppKit
import SwiftUI

@MainActor
final class MemoryInletController {
    private var panel: MemoryInletPanel?
    private let model = MemoryInletModel()
    private let appStore: AppStore

    init(appStore: AppStore) {
        self.appStore = appStore
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }

        guard let panel else { return }
        model.wake()
        position(panel, size: panel.frame.size)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        appStore.hideMemoryInlet()
    }

    private func makePanel() -> MemoryInletPanel {
        let initialSize = CGSize(width: 520, height: 118)
        let rootView = MemoryInletView(
            model: model,
            fragmentStore: appStore.fragmentStore,
            onClose: { [weak self] in self?.hide() },
            onPreferredSizeChange: { [weak self] size in
                self?.resize(to: size)
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        let panel = MemoryInletPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.title = "Brain Dump Memory Inlet"
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        position(panel, size: initialSize)
        return panel
    }

    private func resize(to size: CGSize) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame(for: size), display: true)
        }
    }

    private func position(_ panel: NSPanel, size: CGSize) {
        panel.setFrame(frame(for: size), display: false)
    }

    private func frame(for size: CGSize) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? .zero
        return NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

final class MemoryInletPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        isMovable = false
        level = .mainMenu + 2
        hasShadow = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
            .transient
        ]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
