import AppKit

@MainActor
final class GlobalShortcutService {
    static let shortcutDescription = "Press ` twice"

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastGravePressDate: Date?
    private let onShortcut: () -> Void
    private let doublePressInterval: TimeInterval

    init(doublePressInterval: TimeInterval = 0.45, onShortcut: @escaping () -> Void) {
        self.doublePressInterval = doublePressInterval
        self.onShortcut = onShortcut
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
    }

    func register() {
        guard localMonitor == nil, globalMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if handlePotentialShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags, timestamp: Date()) {
                return nil
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                _ = self.handlePotentialShortcut(
                    keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags,
                    timestamp: Date()
                )
            }
        }
    }

    @discardableResult
    func handlePotentialShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, timestamp: Date) -> Bool {
        guard keyCode == 50, allowsShortcutModifiers(modifierFlags) else {
            lastGravePressDate = nil
            return false
        }

        defer {
            lastGravePressDate = timestamp
        }

        guard let lastGravePressDate else {
            return false
        }

        let elapsed = timestamp.timeIntervalSince(lastGravePressDate)
        if elapsed <= doublePressInterval {
            self.lastGravePressDate = nil
            onShortcut()
            return true
        }

        return false
    }

    private func allowsShortcutModifiers(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let disallowed = modifierFlags.intersection([.command, .control, .option])
        return disallowed.isEmpty
    }
}
