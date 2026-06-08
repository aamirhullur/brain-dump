import AppKit

@MainActor
final class GlobalShortcutService {
    static let shortcutDescription = "Press ` twice"

    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var eventTapContext: GlobalShortcutEventTapContext?
    private let detector: GraveShortcutDetector
    private let onShortcut: () -> Void

    init(doublePressInterval: TimeInterval = 0.45, onShortcut: @escaping () -> Void) {
        detector = GraveShortcutDetector(doublePressInterval: doublePressInterval)
        self.onShortcut = onShortcut
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    func register() {
        guard localMonitor == nil, eventTap == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if handlePotentialShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags, timestamp: Date()) {
                return nil
            }
            return event
        }

        registerEventTap()
    }

    @discardableResult
    func handlePotentialShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, timestamp: Date) -> Bool {
        if detector.handlePotentialShortcut(keyCode: keyCode, modifierFlags: modifierFlags, timestamp: timestamp) {
            onShortcut()
            return true
        }
        return false
    }

    private func registerEventTap() {
        let context = GlobalShortcutEventTapContext(detector: GraveShortcutDetector(doublePressInterval: detector.doublePressInterval)) { [weak self] in
            Task { @MainActor in
                self?.onShortcut()
            }
        }
        eventTapContext = context

        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: globalShortcutEventTapCallback,
            userInfo: pointer
        ) else {
            return
        }

        eventTap = tap
        eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let eventTapRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

private final class GlobalShortcutEventTapContext {
    let detector: GraveShortcutDetector
    let onShortcut: () -> Void
    private var pendingReplayToken = 0
    private let replayMarker: Int64 = 0x42445250

    init(detector: GraveShortcutDetector, onShortcut: @escaping () -> Void) {
        self.detector = detector
        self.onShortcut = onShortcut
    }

    func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == replayMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        guard detector.isPotentialShortcut(keyCode: keyCode, modifierFlags: modifierFlags) else {
            cancelPendingReplay()
            return Unmanaged.passUnretained(event)
        }

        if detector.handlePotentialShortcut(keyCode: keyCode, modifierFlags: modifierFlags, timestamp: Date()) {
            cancelPendingReplay()
            onShortcut()
            return nil
        }

        scheduleReplay(of: event)
        return nil
    }

    private func scheduleReplay(of event: CGEvent) {
        pendingReplayToken += 1
        let token = pendingReplayToken
        guard let eventToReplay = event.copy() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + detector.doublePressInterval) { [weak self] in
            guard let self, token == pendingReplayToken else { return }
            eventToReplay.setIntegerValueField(.eventSourceUserData, value: replayMarker)
            eventToReplay.post(tap: .cghidEventTap)
        }
    }

    private func cancelPendingReplay() {
        pendingReplayToken += 1
    }
}

private let globalShortcutEventTapCallback: CGEventTapCallBack = { _, type, event, userData in
    guard type == .keyDown, let userData else {
        return Unmanaged.passUnretained(event)
    }

    let context = Unmanaged<GlobalShortcutEventTapContext>.fromOpaque(userData).takeUnretainedValue()
    return context.handle(event: event)
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
