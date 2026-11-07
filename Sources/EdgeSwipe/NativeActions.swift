import AppKit
import GestureCore
import PrivateMac

// A stroke snapshots its app order. Activating an app cannot reorder that
// same stroke or leave a synthetic Command key held after interruption.
final class AppCycle {
    private let applications: [NSRunningApplication]
    private var index = 0

    init(recent: [pid_t]) {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let order = [front].compactMap { $0 } + recent
        applications = running.sorted {
            let lhs = order.firstIndex(of: $0.processIdentifier) ?? Int.max
            let rhs = order.firstIndex(of: $1.processIdentifier) ?? Int.max
            return lhs == rhs ? $0.processIdentifier < $1.processIdentifier : lhs < rhs
        }
    }

    func step(_ direction: Direction) -> Bool {
        guard applications.count > 1 else { return false }
        for _ in applications.indices {
            index = (index + direction.rawValue + applications.count) % applications.count
            let app = applications[index]
            if !app.isTerminated { return app.activate(options: []) }
        }
        return false
    }
}

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

    static func step(_ action: GestureAction, _ direction: Direction, apps: AppCycle?, whileValid: () -> Bool) throws -> LevelChange? {
        guard whileValid() else { throw ControlFailure.cancelled }
        let accepted: Bool
        switch action {
        case .switchApps: accepted = apps?.step(direction) ?? false
        case .scrubVideo: accepted = SystemInput.key(direction == .up ? 124 : 123, whileValid: whileValid)
        case .media: accepted = SystemInput.media(direction == .up ? .next : .previous, whileValid: whileValid)
        default: return nil
        }
        return accepted ? LevelChange(level: 0.5) : nil
    }
}
