import Foundation

enum MemoryInletState: Equatable {
    case dormant
    case awake
    case capture(CaptureIntent)
    case progress
}
