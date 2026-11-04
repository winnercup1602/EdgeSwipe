public enum Control: Equatable, Sendable {
    case volume, brightness

    public static let stepSize = 1.0 / 16

    public var minimum: Double { self == .brightness ? Self.stepSize : 0 }
}

public enum Direction: Int, Equatable, Sendable {
    case down = -1, up = 1
}

public enum Touch: Equatable, Sendable {
    case none, single(id: Int32, x: Double, y: Double), invalid
}

public enum Transition: Equatable, Sendable {
    case unchanged, started(Control), recognized, ended
}

public struct EdgeGesture {
    private struct Stroke {
        let id: Int32
        let control: Control
        let x: Double
        let y: Double
        var lastY: Double
        var travel: Double = 0
    }

    private enum State {
        case idle, blocked, candidate(Stroke), active(Stroke)
    }

    private var state = State.idle
    private static let edgeWidth = 0.05
    private static let holdWidth = 0.08
    private static let intentDistance = 0.022
    private static let horizontalLimit = 0.030
    private static let stepDistance = 0.045

    public init() {}

    public mutating func update(_ touch: Touch) -> Transition {
        switch touch {
        case .none:
            let changed = cancel()
            state = .idle
            return changed ? .ended : .unchanged
        case .invalid:
            return cancel() ? .ended : .unchanged
        case let .single(id, x, y):
            guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
                return cancel() ? .ended : .unchanged
            }
            switch state {
            case .idle:
                let control: Control
                if x <= Self.edgeWidth {
                    control = .volume
                } else if x >= 1 - Self.edgeWidth {
                    control = .brightness
                } else {
                    state = .blocked
                    return .unchanged
                }
                state = .candidate(Stroke(id: id, control: control, x: x, y: y, lastY: y))
                return .started(control)
            case .blocked:
                return .unchanged
            case let .candidate(stroke):
                let vertical = abs(y - stroke.y)
                let horizontal = abs(x - stroke.x)
                guard matches(stroke, id: id, x: x), horizontal < Self.horizontalLimit,
                      horizontal < Self.intentDistance || vertical > horizontal else {
                    _ = cancel()
                    return .ended
                }
                guard vertical >= Self.intentDistance, vertical >= 1.6 * horizontal else {
                    return .unchanged
                }
                var active = stroke
                active.lastY = y
                active.travel = y - stroke.y
                state = .active(active)
                return .recognized
            case var .active(stroke):
                guard matches(stroke, id: id, x: x), abs(x - stroke.x) < 0.04 else {
                    _ = cancel()
                    return .ended
                }
                stroke.travel += y - stroke.lastY
                stroke.lastY = y
                state = .active(stroke)
                return .unchanged
            }
        }
    }

    public mutating func nextStep() -> Direction? {
        guard case var .active(stroke) = state,
              abs(stroke.travel) >= Self.stepDistance - 1e-9 else { return nil }
        let direction: Direction = stroke.travel > 0 ? .up : .down
        stroke.travel -= Double(direction.rawValue) * Self.stepDistance
        state = .active(stroke)
        return direction
    }

    public mutating func discardTravel(in direction: Direction) {
        guard case var .active(stroke) = state,
              stroke.travel * Double(direction.rawValue) > 0 else { return }
        stroke.travel = 0
        state = .active(stroke)
    }

    @discardableResult
    public mutating func cancel() -> Bool {
        let wasTracking: Bool
        switch state {
        case .candidate, .active: wasTracking = true
        case .idle, .blocked: wasTracking = false
        }
        state = .blocked
        return wasTracking
    }

    private func matches(_ stroke: Stroke, id: Int32, x: Double) -> Bool {
        guard id == stroke.id else { return false }
        return stroke.control == .volume ? x <= Self.holdWidth : x >= 1 - Self.holdWidth
    }
}
