import Foundation

// A recognized edge tap can also produce macOS tap-to-click events. Consume
// just that nearby, short-lived left-click pair, never an unrelated click.
public struct TapClickFilter {
    private var deadline = -Double.infinity
    private var x = 0.0
    private var y = 0.0
    private var swallowing = false
    public init() {}
    public mutating func arm(at time: Double, x: Double, y: Double) {
        self.x = x; self.y = y; deadline = time + 0.10; swallowing = false
    }
    public mutating func reset() { deadline = -.infinity; swallowing = false }
    public func suppressingPress(at time: Double) -> Bool { swallowing && time <= deadline }
    public mutating func down(at time: Double, x: Double, y: Double) -> Bool {
        guard time <= deadline, hypot(self.x - x, self.y - y) <= 2 else { reset(); return false }
        swallowing = true
        deadline = time + 0.2
        return true
    }
    public mutating func up(at time: Double) -> Bool {
        let result = suppressingPress(at: time)
        reset()
        return result
    }
}
