import AppKit
import SwiftUI

@MainActor
enum NotchMetrics {
    /// Dormant size must match the physical notch exactly or the window
    /// reads as a floating blob under the menu bar.
    static func dormantSize(for screen: NSScreen?) -> CGSize {
        guard let screen else { return CGSize(width: 184, height: 32) }
        if screen.safeAreaInsets.top > 0,
           let leftArea = screen.auxiliaryTopLeftArea?.width,
           let rightArea = screen.auxiliaryTopRightArea?.width {
            return CGSize(
                width: screen.frame.width - leftArea - rightArea + 4,
                height: screen.safeAreaInsets.top
            )
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: 184, height: max(24, menuBarHeight))
    }

    static func hasNotch(_ screen: NSScreen?) -> Bool {
        (screen?.safeAreaInsets.top ?? 0) > 0
    }
}

@MainActor
final class MemoryInletController {
    private var panel: MemoryInletPanel?
    private let model = MemoryInletModel()
    private let appStore: AppStore
    private var mouseMonitors: [Any] = []

    init(appStore: AppStore) {
        self.appStore = appStore
    }

    deinit {
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
    }

    func installDormant() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        model.collapse()
        panel.orderFrontRegardless()
        startMouseMonitoring()
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }

        guard let panel else { return }
        model.wake()
        position(panel, size: panel.frame.size)
        panel.makeKeyAndOrderFront(nil)
        startMouseMonitoring()
    }

    func hide() {
        model.collapse()
        appStore.hideMemoryInlet()
    }

    private func startMouseMonitoring() {
        guard mouseMonitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMoved()
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler) {
            mouseMonitors.append(global)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event)
            return event
        }
        if let local {
            mouseMonitors.append(local)
        }
    }

    private func handleMouseMoved() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation

        switch model.state {
        case .dormant:
            let wakeZone = panel.frame.insetBy(dx: -8, dy: -8)
            if wakeZone.contains(mouse) {
                model.wake()
                panel.orderFrontRegardless()
            }
        case .awake, .progress:
            let keepZone = panel.frame.insetBy(dx: -40, dy: -40)
            if !keepZone.contains(mouse) {
                model.collapse()
            }
        case .capture:
            break
        }
    }

    private func makePanel() -> MemoryInletPanel {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let initialSize = CGSize(width: 520, height: 118)
        let rootView = MemoryInletView(
            model: model,
            fragmentStore: appStore.fragmentStore,
            collapsedSize: NotchMetrics.dormantSize(for: screen),
            onClose: { [weak self] in self?.hide() },
            onPreferredSizeChange: { [weak self] size in
                self?.resize(to: size)
            },
            onScreenshotCapture: { [weak self] in
                self?.hide()
                self?.appStore.captureScreenshot()
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
