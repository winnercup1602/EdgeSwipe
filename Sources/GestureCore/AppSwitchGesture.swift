public enum AppSwitchKey: CaseIterable, Hashable, Sendable {
    case commandDown, next, previous, accept, cancel, commandUp
}

// Command belongs to one stroke, never to the lifetime of the application.
// Renew only from real contact frames so a stalled input cannot keep it held.
public struct AppSwitchGesture {
    public static let timeout = 0.45
    private enum State { case idle, tracking, finished }
    private var state = State.idle
    private var deadline = -Double.infinity
    public init() {}

    public mutating func step(forward: Bool, at time: Double) -> [AppSwitchKey] {
        guard state != .finished else { return [] }
        if state == .tracking, time >= deadline { return finish(commit: false) }
        let opening = state == .idle
        state = .tracking
        if opening { deadline = time + Self.timeout }
        return (opening ? [.commandDown] : []) + [forward ? .next : .previous]
    }

    public mutating func renew(at time: Double) -> [AppSwitchKey] {
        guard state == .tracking else { return [] }
        if time >= deadline { return finish(commit: false) }
        deadline = time + Self.timeout
        return []
    }

    public mutating func expire(at time: Double) -> [AppSwitchKey] {
        state == .tracking && time >= deadline ? finish(commit: false) : []
    }

    public mutating func finish(commit: Bool, physicalCommandHeld: Bool = false) -> [AppSwitchKey] {
        guard state != .finished else { return [] }
        let held = state == .tracking
        state = .finished
        guard held else { return [] }
        // Return confirms even if the user is holding Command as a gesture key.
        return (commit ? (physicalCommandHeld ? [.accept] : []) : [.cancel]) + [.commandUp]
    }
}
