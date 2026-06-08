import AppKit
import Foundation
import Testing
@testable import BrainDump

@MainActor
struct GlobalShortcutServiceTests {
    @Test
    func doubleGravePressTriggersShortcutOnce() {
        var triggerCount = 0
        let service = GlobalShortcutService {
            triggerCount += 1
        }
        let firstPress = Date()

        #expect(service.handlePotentialShortcut(keyCode: 50, modifierFlags: [], timestamp: firstPress) == false)
        #expect(service.handlePotentialShortcut(keyCode: 50, modifierFlags: [], timestamp: firstPress.addingTimeInterval(0.2)) == true)
        #expect(triggerCount == 1)
    }

    @Test
    func slowGravePressesDoNotTriggerShortcut() {
        var triggerCount = 0
        let service = GlobalShortcutService {
            triggerCount += 1
        }
        let firstPress = Date()

        #expect(service.handlePotentialShortcut(keyCode: 50, modifierFlags: [], timestamp: firstPress) == false)
        #expect(service.handlePotentialShortcut(keyCode: 50, modifierFlags: [], timestamp: firstPress.addingTimeInterval(0.8)) == false)
        #expect(triggerCount == 0)
    }

    @Test
    func commandModifiedGravePressDoesNotTriggerShortcut() {
        var triggerCount = 0
        let service = GlobalShortcutService {
            triggerCount += 1
        }
        let firstPress = Date()

        #expect(service.handlePotentialShortcut(keyCode: 50, modifierFlags: [.command], timestamp: firstPress) == false)
        #expect(service.handlePotentialShortcut(keyCode: 50, modifierFlags: [.command], timestamp: firstPress.addingTimeInterval(0.2)) == false)
        #expect(triggerCount == 0)
    }
}
