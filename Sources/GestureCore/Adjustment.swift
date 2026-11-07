public struct LevelChange: Equatable, Sendable {
    public let level: Double
    public init(level: Double) { self.level = level }

    // The nonzero floor keeps the lowest step perceptible. The gain grows
    // linearly with the resulting level, independent of direction.
    public var hapticGain: Float { Float(0.22 + 0.58 * level) }
}

public enum Adjustment {
    public static func apply(
        _ control: Control,
        _ direction: Direction,
        step: Double = Control.stepSize,
        read: () throws -> Double,
        write: (Double) throws -> Double
    ) throws -> LevelChange? {
        guard step.isFinite, step > 0, step <= 1 else { throw InvalidLevel() }
        let current = try read()
        guard current.isFinite, (0...1).contains(current) else { throw InvalidLevel() }
        let next = min(1, max(control.minimum, current + Double(direction.rawValue) * step))
        let difference = next - current
        guard difference * Double(direction.rawValue) > 0.000_01 else { return nil }
        let applied = try write(next)
        guard applied.isFinite, (0...1).contains(applied) else { throw InvalidLevel() }
        guard (applied - current) * Double(direction.rawValue) > 0.000_01 else { return nil }
        return LevelChange(level: applied)
    }

    public struct InvalidLevel: Error {}
}
