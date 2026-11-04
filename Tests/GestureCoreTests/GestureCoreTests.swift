import Darwin

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () throws -> Bool,
                    line: UInt = #line) throws {
    guard try condition() else { throw TestFailure(description: "Expectation failed at line \(line)") }
}

private func throwsError(_ operation: () throws -> Void, line: UInt = #line) throws {
    do { try operation() } catch { return }
    throw TestFailure(description: "Expected an error at line \(line)")
}

private func finger(_ x: Double, _ y: Double, id: Int32 = 1) -> Touch {
    .single(id: id, x: x, y: y)
}

@main
struct GestureCoreTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("left up, right down, consecutive strokes", directions),
            ("center start never activates at an edge", centerStart),
            ("horizontal motion and leaving edge cancel", edgeExit),
            ("multitouch, contact replacement, and explicit cancel", otherContacts),
            ("reversal and travel discard at a limit", reversal),
            ("volume and brightness steps and clamps", adjustment),
            ("successful-write feedback and increasing gain", feedback)
        ]
        var failures = 0
        for (name, run) in tests {
            do {
                try run()
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }
        print("\(tests.count - failures)/\(tests.count) cases passed")
        if failures > 0 { exit(1) }
    }

    private static func directions() throws {
        var gesture = EdgeGesture()
        try expect(gesture.update(finger(0.03, 0.30)) == .started(.volume))
        try expect(gesture.update(finger(0.03, 0.31)) == .unchanged)
        try expect(gesture.update(finger(0.03, 0.325)) == .recognized)
        try expect(gesture.nextStep() == nil)
        try expect(gesture.update(finger(0.03, 0.345)) == .unchanged)
        try expect(gesture.nextStep() == .up)
        try expect(gesture.nextStep() == nil)
        try expect(gesture.update(.none) == .ended)
        try expect(gesture.update(finger(0.97, 0.75)) == .started(.brightness))
        try expect(gesture.update(finger(0.97, 0.705)) == .recognized)
        try expect(gesture.nextStep() == .down)
    }

    private static func centerStart() throws {
        var gesture = EdgeGesture()
        try expect(gesture.update(finger(0.2, 0.5)) == .unchanged)
        try expect(gesture.update(finger(0.02, 0.5)) == .unchanged)
        try expect(gesture.update(finger(0.02, 0.8)) == .unchanged)
        try expect(gesture.nextStep() == nil)
    }

    private static func edgeExit() throws {
        var gesture = EdgeGesture()
        try expect(gesture.update(finger(0.025, 0.5)) == .started(.volume))
        try expect(gesture.update(finger(0.055, 0.51)) == .ended)
        try expect(gesture.update(finger(0.03, 0.7)) == .unchanged)
        _ = gesture.update(.none)
        try expect(gesture.update(finger(0.045, 0.5)) == .started(.volume))
        try expect(gesture.update(finger(0.05, 0.55)) == .recognized)
        try expect(gesture.update(finger(0.085, 0.57)) == .ended)
        try expect(gesture.nextStep() == nil)
    }

    private static func otherContacts() throws {
        var gesture = EdgeGesture()
        _ = gesture.update(finger(0.97, 0.5))
        try expect(gesture.update(finger(0.97, 0.55)) == .recognized)
        try expect(gesture.update(.invalid) == .ended)
        try expect(gesture.update(finger(0.97, 0.6)) == .unchanged)
        try expect(gesture.nextStep() == nil)

        _ = gesture.update(.none)
        _ = gesture.update(finger(0.97, 0.5))
        try expect(gesture.update(finger(0.97, 0.55, id: 2)) == .ended)
        _ = gesture.update(.none)
        _ = gesture.update(finger(0.97, 0.5))
        try expect(gesture.cancel())
        try expect(gesture.update(finger(0.97, 0.55)) == .unchanged)
        try expect(gesture.nextStep() == nil)
    }

    private static func reversal() throws {
        var gesture = EdgeGesture()
        _ = gesture.update(finger(0.02, 0.45))
        _ = gesture.update(finger(0.02, 0.55))
        try expect(gesture.nextStep() == .up)
        try expect(gesture.nextStep() == .up)
        _ = gesture.update(finger(0.02, 0.49))
        try expect(gesture.nextStep() == .down)
        _ = gesture.update(finger(0.02, 0.61))
        try expect(gesture.nextStep() == .up)
        gesture.discardTravel(in: .up)
        try expect(gesture.nextStep() == nil)
        _ = gesture.update(finger(0.02, 0.565))
        try expect(gesture.nextStep() == .down)
    }

    private static func adjustment() throws {
        var level = 0.35
        let up = try Adjustment.apply(.volume, .up, read: { level }, write: {
            level = $0
            return $0
        })
        try expect(abs((up?.level ?? -1) - 0.4125) < 1e-9)
        let down = try Adjustment.apply(.volume, .down, read: { level }, write: {
            level = $0
            return $0
        })
        try expect(abs((down?.level ?? -1) - 0.35) < 1e-9)

        let forbiddenWrite: (Double) throws -> Double = { _ in throw TestFailure(description: "Unexpected write") }
        level = 0.03
        try expect(try Adjustment.apply(.volume, .down, read: { level }, write: {
            level = $0
            return $0
        })?.level == 0)
        try expect(try Adjustment.apply(.volume, .down, read: { level }, write: forbiddenWrite) == nil)
        level = 0.98
        try expect(try Adjustment.apply(.brightness, .up, read: { level }, write: {
            level = $0
            return $0
        })?.level == 1)
        try expect(try Adjustment.apply(.brightness, .up, read: { level }, write: forbiddenWrite) == nil)
        level = 0.08
        try expect(try Adjustment.apply(.brightness, .down, read: { level }, write: {
            level = $0
            return $0
        })?.level == 1.0 / 16)
        try expect(try Adjustment.apply(.brightness, .down, read: { 0.02 }, write: forbiddenWrite) == nil)
    }

    private static func feedback() throws {
        struct HardwareError: Error {}
        try throwsError { _ = try Adjustment.apply(.volume, .up, read: { 0.5 }, write: { _ in throw HardwareError() }) }
        try throwsError { _ = try Adjustment.apply(.volume, .up, read: { .nan }, write: { $0 }) }
        var previous: Float = 0
        for level in [0.0625, 0.5625, 1.0] {
            let change = try Adjustment.apply(.volume, .up, read: { level - 0.0625 }, write: { $0 })
            let gain = change?.hapticGain ?? -1
            try expect(gain > previous)
            try expect(abs(gain - Float(0.22 + 0.58 * level)) < 1e-6)
            previous = gain
        }
        let rounded = try Adjustment.apply(.brightness, .up, read: { 0.42 }, write: { _ in 0.48 })
        try expect(rounded?.level == 0.48)
        try expect(try Adjustment.apply(.brightness, .up, read: { 0.42 }, write: { _ in 0.42 }) == nil)
    }
}
