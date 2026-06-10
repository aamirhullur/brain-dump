import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalShortcutService {
    static let shortcutDescription = "Option + ` (or hover over the notch)"

    private var localMonitor: Any?
    private let hotKeys = HotKeyService()
    private let detector: GraveShortcutDetector
    private let onShortcut: () -> Void
    private let onPaletteShortcut: () -> Void
    private let onScreenshotShortcut: () -> Void

    init(
        doublePressInterval: TimeInterval = 0.45,
        onShortcut: @escaping () -> Void,
        onPaletteShortcut: @escaping () -> Void = {},
        onScreenshotShortcut: @escaping () -> Void = {}
    ) {
        detector = GraveShortcutDetector(doublePressInterval: doublePressInterval)
        self.onShortcut = onShortcut
        self.onPaletteShortcut = onPaletteShortcut
        self.onScreenshotShortcut = onScreenshotShortcut
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    func register() {
        guard localMonitor == nil else { return }

        // Double-` only works while the app is frontmost; watching it
        // globally would need a CGEvent tap and Accessibility permission.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if handlePotentialShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags, timestamp: Date()) {
                return nil
            }
            return event
        }

        // System-wide hotkeys via Carbon; no permissions required.
        hotKeys.register(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(optionKey)) { [weak self] in
            self?.onPaletteShortcut()
        }
        hotKeys.register(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(optionKey | shiftKey)) { [weak self] in
            self?.onScreenshotShortcut()
        }
    }

    @discardableResult
    func handlePotentialShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, timestamp: Date) -> Bool {
        if detector.handlePotentialShortcut(keyCode: keyCode, modifierFlags: modifierFlags, timestamp: timestamp) {
            onShortcut()
            return true
        }
        return false
    }
}

enum ScreenshotShortcutDetector {
    static let shortcutDescription = "Option + Shift + 2"
    private static let twoKeyCode: UInt16 = 19

    static func matches(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard keyCode == twoKeyCode else { return false }
        let relevant = modifierFlags.intersection([.command, .control, .option, .shift])
        return relevant == [.option, .shift]
    }
}

final class GraveShortcutDetector {
    private var lastGravePressDate: Date?
    let doublePressInterval: TimeInterval

    init(doublePressInterval: TimeInterval) {
        self.doublePressInterval = doublePressInterval
    }

    func handlePotentialShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, timestamp: Date) -> Bool {
        guard isPotentialShortcut(keyCode: keyCode, modifierFlags: modifierFlags) else {
            lastGravePressDate = nil
            return false
        }

        guard let lastGravePressDate else {
            self.lastGravePressDate = timestamp
            return false
        }

        let elapsed = timestamp.timeIntervalSince(lastGravePressDate)
        if elapsed <= doublePressInterval {
            self.lastGravePressDate = nil
            return true
        }

        self.lastGravePressDate = timestamp
        return false
    }

    func isPotentialShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        keyCode == 50 && allowsShortcutModifiers(modifierFlags)
    }

    private func allowsShortcutModifiers(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let disallowed = modifierFlags.intersection([.command, .control, .option])
        return disallowed.isEmpty
    }
}
