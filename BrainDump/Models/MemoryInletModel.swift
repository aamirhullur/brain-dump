import Foundation
import Observation

@Observable
@MainActor
final class MemoryInletModel {
    var state: MemoryInletState = .awake

    func wake() {
        state = .awake
    }

    func collapse() {
        state = .dormant
    }
}
