public enum Control: Equatable, Sendable {
    case volume, brightness, keyboardBrightness

    public static let stepSize = 1.0 / 16

    public var minimum: Double { self == .brightness ? Self.stepSize : 0 }
}

public enum Edge: String, CaseIterable, Equatable, Sendable {
    case left, right, top, bottom

    public var vertical: Bool { self == .left || self == .right }
}

public enum Direction: Int, Equatable, Sendable {
    case down = -1, up = 1
}

public enum Touch: Equatable, Sendable {
    case none, single(id: Int32, x: Double, y: Double), invalid
}

public enum Transition: Equatable, Sendable {
    case unchanged, started(Edge), recognized, ended
}

public struct EdgeGesture {
    private struct Stroke {
        let id: Int32
        let edge: Edge
        let x: Double
        let y: Double
        let startedAt: Double
        var lastProgress: Double
        var travel: Double = 0
    }

    private enum State {
        case idle, blocked, candidate(Stroke), active(Stroke)
    }

    private var state = State.idle
    private let configuration: GestureConfiguration
    private static let intentDistance = 0.022
    private static let horizontalLimit = 0.030
    private static let stepDistance = 0.045

    public init(configuration: GestureConfiguration = GestureConfiguration()) {
        self.configuration = configuration
    }

    public mutating func update(_ touch: Touch, at time: Double? = nil) -> Transition {
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
                let distances: [(Edge, Double)] = [(.left, x), (.right, 1 - x), (.top, 1 - y), (.bottom, y)]
                guard let edge = distances.filter({ edge, distance in
                    configuration.enabledEdges.contains(edge) && distance <= configuration.width.fraction
                        && (!configuration.bottomQuarterOnly || !edge.vertical || y <= 0.25)
                }).min(by: { $0.1 < $1.1 })?.0 else {
                    state = .blocked
                    return .unchanged
                }
                state = .candidate(Stroke(id: id, edge: edge, x: x, y: y, startedAt: time ?? -.infinity,
                                          lastProgress: edge.vertical ? y : x))
                return .started(edge)
            case .blocked:
                return .unchanged
            case let .candidate(stroke):
                let vertical = abs(stroke.edge.vertical ? y - stroke.y : x - stroke.x)
                let horizontal = abs(stroke.edge.vertical ? x - stroke.x : y - stroke.y)
                guard matches(stroke, id: id, x: x, y: y), horizontal < Self.horizontalLimit,
                      horizontal < Self.intentDistance || vertical > horizontal else {
                    _ = cancel()
                    return .ended
                }
                guard vertical >= Self.intentDistance, vertical >= 1.6 * horizontal,
                      (time ?? .infinity) - stroke.startedAt >= configuration.singleFingerDelay else {
                    return .unchanged
                }
                var active = stroke
                active.lastProgress = stroke.edge.vertical ? y : x
                active.travel = stroke.edge.vertical ? y - stroke.y : x - stroke.x
                state = .active(active)
                return .recognized
            case var .active(stroke):
                guard matches(stroke, id: id, x: x, y: y), abs(stroke.edge.vertical ? x - stroke.x : y - stroke.y) < 0.04 else {
                    _ = cancel()
                    return .ended
                }
                let progress = stroke.edge.vertical ? y : x
                stroke.travel += progress - stroke.lastProgress
                stroke.lastProgress = progress
                state = .active(stroke)
                return .unchanged
            }
        }
    }

    public mutating func nextStep(at time: Double = .infinity) -> Direction? {
        guard case var .active(stroke) = state, time - stroke.startedAt >= configuration.singleFingerDelay,
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

    private func matches(_ stroke: Stroke, id: Int32, x: Double, y: Double) -> Bool {
        guard id == stroke.id else { return false }
        let hold = configuration.width.fraction + 0.03
        if configuration.bottomQuarterOnly && stroke.edge.vertical && y > 0.25 { return false }
        switch stroke.edge {
        case .left: return x <= hold
        case .right: return x >= 1 - hold
        case .top: return y >= 1 - hold
        case .bottom: return y <= hold
        }
    }
}
