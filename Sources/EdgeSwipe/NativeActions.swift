import GestureCore
import PrivateMac

final class NativeActions {
    // Accessed only from the serial control queue.
    private var mutedLevels: [UInt32: Double] = [:]

    func tap(_ action: TapAction, whileValid: () -> Bool) throws -> LevelChange? {
        guard whileValid() else { throw ControlFailure.cancelled }
        switch action {
        case .middleClick:
            guard SystemInput.onMain({ whileValid() && SystemInput.middleClick() }) else { throw ControlFailure.inputUnavailable }
        case .playPause:
            guard SystemInput.media(.playPause, whileValid: whileValid) else { throw ControlFailure.inputUnavailable }
        case .corner(.mute):
            return LevelChange(level: try AudioOutput.current().toggleMute(previous: &mutedLevels))
        case .corner(.screenshot):
            guard SystemInput.key(23, flags: [.maskCommand, .maskShift], whileValid: whileValid) else { throw ControlFailure.inputUnavailable }
        case .corner(.off): return nil
        }
        return LevelChange(level: 0.5)
    }

    static func step(_ action: GestureAction, _ direction: Direction, apps: AppSwitcher?, whileValid: () -> Bool) throws -> LevelChange? {
        guard whileValid() else { throw ControlFailure.cancelled }
        let accepted: Bool
        switch action {
        case .switchApps:
            guard apps?.step(forward: direction == .up) == true else { throw ControlFailure.inputUnavailable }
            accepted = true
        case .scrubVideo: accepted = SystemInput.key(direction == .up ? 124 : 123, whileValid: whileValid)
        case .media: accepted = SystemInput.media(direction == .up ? .next : .previous, whileValid: whileValid)
        default: return nil
        }
        return accepted ? LevelChange(level: 0.5) : nil
    }
}
