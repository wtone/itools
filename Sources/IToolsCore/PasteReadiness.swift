import Foundation

public enum PasteReadiness: Equatable {
    case waiting, ready, targetClosed, clipboardChanged, timedOut
    public static func evaluate(targetAlive: Bool, clipboardUnchanged: Bool, foreground: Bool,
                                modifiersReleased: Bool, timedOut: Bool) -> PasteReadiness {
        if !targetAlive { return .targetClosed }
        if !clipboardUnchanged { return .clipboardChanged }
        if timedOut { return .timedOut }
        if foreground && modifiersReleased { return .ready }
        return .waiting
    }
}
