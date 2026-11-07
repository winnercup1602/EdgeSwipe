import CoreGraphics
import Foundation
import GestureCore

// Use an independent event source so synthetic Command does not satisfy the
// physical Hold-to-Slide gate or replace the user's modifier-key state.
public final class AppSwitcher {
    private let lock = NSLock()
    private let source: CGEventSource
    private var gesture = AppSwitchGesture()
    private let events: [AppSwitchKey: [CGEvent]]
    private let watchdog: DispatchSourceTimer

    public init?() {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        source.localEventsSuppressionInterval = 0
        self.source = source
        var events: [AppSwitchKey: [CGEvent]] = [:]
        for key in AppSwitchKey.allCases {
            let code: CGKeyCode
            switch key {
            case .commandDown, .commandUp: code = 55
            case .next, .previous: code = 48
            case .accept: code = 36
            case .cancel: code = 53
            }
            let modifier = key == .commandDown || key == .commandUp
            let states = modifier ? [key == .commandDown] : [true, false]
            var pair: [CGEvent] = []
            for down in states {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return nil }
                if modifier { event.type = .flagsChanged }
                event.flags = key == .previous ? [.maskCommand, .maskShift] : .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: SystemInput.eventTag)
                pair.append(event)
            }
            events[key] = pair
        }
        self.events = events
        watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "io.github.winnercup1602.edgeswipe.app-switcher"))
        watchdog.schedule(deadline: .now() + 0.05, repeating: 0.05)
        watchdog.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            self.post(self.gesture.expire(at: ProcessInfo.processInfo.systemUptime))
        }
        watchdog.resume()
    }

    deinit { finish(commit: false); watchdog.cancel() }

    @discardableResult
    public func step(forward: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard CGPreflightPostEventAccess() else {
            post(gesture.finish(commit: false))
            return false
        }
        let keys = gesture.step(forward: forward, at: ProcessInfo.processInfo.systemUptime)
        post(keys)
        return keys.contains(forward ? .next : .previous)
    }

    public func renew() {
        lock.lock()
        defer { lock.unlock() }
        post(gesture.renew(at: ProcessInfo.processInfo.systemUptime))
    }

    public func finish(commit: Bool) {
        lock.lock()
        defer { lock.unlock() }
        post(gesture.finish(commit: commit, physicalCommandHeld: Self.physicalFlags.contains(.maskCommand)))
    }

    private static var physicalFlags: CGEventFlags { CGEventSource.flagsState(.hidSystemState) }

    private func post(_ keys: [AppSwitchKey]) {
        for key in keys {
            for event in events[key] ?? [] {
                // Cleanup must still be attempted after permission loss, and
                // must preserve modifiers that are physically still held.
                if key == .commandUp { event.flags = Self.physicalFlags }
                // Session injection leaves the hardware modifier table intact.
                event.post(tap: .cgSessionEventTap)
            }
        }
    }
}
