import Foundation

private struct ExpandedFailure: Error { let line: UInt }
private func check(_ condition: @autoclosure () throws -> Bool, line: UInt = #line) throws {
    if try !condition() { throw ExpandedFailure(line: line) }
}
private func point(_ x: Double, _ y: Double) -> Touch { .single(id: 1, x: x, y: y) }
private func contact(_ id: Int32, _ x: Double = 0.5, _ y: Double = 0.02, size: Double = 0.3, major: Double = 7) -> Finger {
    Finger(id: id, x: x, y: y, size: size, majorAxis: major)
}

struct ExpandedGestureTests {
    static let cases: [(String, () throws -> Void)] = [
        ("top and bottom edges use horizontal motion", horizontal),
        ("edge width and lower quarter restrict starts", regions),
        ("two-finger arrival cancels before the first step", grace),
        ("corner double tap, timeout, and cancellation", corners),
        ("three-finger tap with staggered touchdown and release", middle),
        ("movement, palms, extra fingers, and contact replacement reject taps", rejectedTaps),
        ("media edge taps do not fire after swipes", media),
        ("haptic presets remain linear and off is silent", haptics),
        ("fine adjustment uses quarter-sized steps", fine),
        ("hold key and independent edge action configuration", configuration),
        ("hold toggle latches only on a chosen key press", keyToggle),
        ("recognized taps consume only their nearby native click pair", tapClicks)
    ]
    static func horizontal() throws {
        var config = GestureConfiguration(); config.enabledEdges = [.top, .bottom]
        for edge in [Edge.top, .bottom] {
            let y = edge == .top ? 0.98 : 0.02
            var gesture = EdgeGesture(configuration: config)
            try check(gesture.update(point(0.5, y)) == .started(edge))
            try check(gesture.update(point(0.55, y), at: 0.1) == .recognized)
            try check(gesture.nextStep(at: 0.1) == .up)
            _ = gesture.update(point(0.49, y), at: 0.2)
            try check(gesture.nextStep(at: 0.2) == .down)
            try check(gesture.update(point(0.48, 0.5), at: 0.3) == .ended)
            try check(gesture.nextStep(at: 0.4) == nil)
        }
    }
    static func regions() throws {
        var config = GestureConfiguration(); config.width = .narrow
        var g = EdgeGesture(configuration: config)
        try check(g.update(point(0.04, 0.5)) == .unchanged)
        config.width = .wide; config.bottomQuarterOnly = true
        g = EdgeGesture(configuration: config)
        try check(g.update(point(0.075, 0.5)) == .unchanged)
        _ = g.update(.none)
        try check(g.update(point(0.075, 0.2)) == .started(.left))
        try check(g.update(point(0.075, 0.24), at: 0.1) == .recognized)
        try check(g.update(point(0.075, 0.26), at: 0.2) == .ended)
    }
    static func grace() throws {
        var g = EdgeGesture()
        _ = g.update(point(0.02, 0.5), at: 1)
        try check(g.update(point(0.02, 0.55), at: 1.01) == .unchanged)
        try check(g.nextStep(at: 1.02) == nil)
        try check(g.update(.invalid, at: 1.03) == .ended)
        try check(g.nextStep(at: 2) == nil)
        _ = g.update(.none, at: 3)
        _ = g.update(point(0.02, 0.5), at: 4)
        _ = g.update(point(0.02, 0.55), at: 4.06)
        try check(g.nextStep(at: 4.06) == .up)
    }
    static func corners() throws {
        var settings = GestureSettings(); settings.corners[.bottomLeft] = .mute
        var tap = TapGesture()
        let f = contact(1, 0.02, 0.02)
        _ = tap.update([f], at: 0, settings: settings)
        try check(tap.update([], at: 0.05, settings: settings) == nil)
        _ = tap.update([f], at: 0.15, settings: settings)
        try check(tap.update([], at: 0.2, settings: settings) == .corner(.mute))
        _ = tap.update([f], at: 1, settings: settings); _ = tap.update([], at: 1.05, settings: settings)
        _ = tap.update([f], at: 2, settings: settings)
        try check(tap.update([], at: 2.05, settings: settings) == nil)
        tap.cancel(); _ = tap.update([], at: 2.1, settings: settings)
        _ = tap.update([f], at: 2.2, settings: settings)
        try check(tap.update([], at: 2.25, settings: settings) == nil)
    }
    static func middle() throws {
        var settings = GestureSettings(); settings.threeFingerClick = true
        var tap = TapGesture()
        let a = contact(1), b = contact(2, 0.6), c = contact(3, 0.7)
        _ = tap.update([a], at: 0, settings: settings)
        _ = tap.update([a,b], at: 0.02, settings: settings)
        _ = tap.update([a,b,c], at: 0.04, settings: settings)
        _ = tap.update([a,b], at: 0.06, settings: settings)
        _ = tap.update([a], at: 0.08, settings: settings)
        try check(tap.update([], at: 0.10, settings: settings) == .middleClick)
    }
    static func rejectedTaps() throws {
        var settings = GestureSettings(); settings.threeFingerClick = true; settings.bottom = .media
        for fingers in [[contact(1, size: 3)], [contact(1, major: 20)], [contact(1),contact(2),contact(3),contact(4)]] {
            var tap = TapGesture(); _ = tap.update(fingers, at: 0, settings: settings)
            try check(tap.update([], at: 0.1, settings: settings) == nil)
        }
        var tap = TapGesture(); _ = tap.update([contact(1)], at: 0, settings: settings)
        _ = tap.update([contact(2)], at: 0.01, settings: settings)
        try check(tap.update([], at: 0.1, settings: settings) == nil)
        tap = TapGesture(); _ = tap.update([contact(1)], at: 0, settings: settings)
        _ = tap.update([contact(1, 0.6)], at: 0.05, settings: settings)
        try check(tap.update([], at: 0.1, settings: settings) == nil)
    }
    static func media() throws {
        var settings = GestureSettings(); settings.bottom = .media
        var tap = TapGesture(); _ = tap.update([contact(1)], at: 0, settings: settings)
        try check(tap.update([], at: 0.1, settings: settings) == .playPause)
        _ = tap.update([contact(1)], at: 1, settings: settings)
        tap.cancel()
        try check(tap.update([], at: 1.1, settings: settings) == nil)
    }
    static func haptics() throws {
        for strength in HapticStrength.allCases {
            let low = strength.gain(level: 0), mid = strength.gain(level: 0.5), high = strength.gain(level: 1)
            if strength == .off { try check(low == 0 && mid == 0 && high == 0) }
            else { try check(low > 0 && low < mid && mid < high && high <= 1); try check(abs((low + high) / 2 - mid) < 0.0001) }
        }
    }
    static func fine() throws {
        let settings: GestureSettings = { var s = GestureSettings(); s.precise = true; return s }()
        let change = try Adjustment.apply(.volume, .up, step: settings.step, read: { 0.5 }, write: { $0 })
        try check(change?.level == 0.515625)
        var wrote = false
        let boundary = try Adjustment.apply(.brightness, .down, step: settings.step, read: { 0.0625 }, write: { wrote = true; return $0 })
        try check(boundary == nil && !wrote)
    }
    static func tapClicks() throws {
        var filter = TapClickFilter()
        filter.arm(at: 1, x: -100, y: 200)
        try check(filter.down(at: 1.03, x: -99, y: 200))
        try check(filter.suppressingPress(at: 1.04))
        try check(filter.up(at: 1.06))
        try check(!filter.down(at: 1.07, x: -100, y: 200))
        filter.arm(at: 2, x: 10, y: 10)
        try check(!filter.down(at: 2.11, x: 10, y: 10))
        filter.arm(at: 3, x: 10, y: 10)
        try check(!filter.down(at: 3.01, x: 100, y: 100))
        filter.arm(at: 4, x: 0, y: 0)
        try check(filter.down(at: 4.01, x: 0, y: 0))
        try check(!filter.up(at: 5))
    }
    static func keyToggle() throws {
        var gate = HoldGate()
        try check(!gate.permits(key: .option, mode: .toggle, flags: 0))
        try check(!gate.flagsChanged(HoldKey.shift.flag, key: .option, mode: .toggle))
        try check(gate.flagsChanged(HoldKey.option.flag, key: .option, mode: .toggle))
        try check(gate.permits(key: .option, mode: .toggle, flags: 0))
        try check(!gate.flagsChanged(HoldKey.option.flag | HoldKey.shift.flag, key: .option, mode: .toggle))
        _ = gate.flagsChanged(0, key: .option, mode: .toggle)
        try check(gate.flagsChanged(HoldKey.option.flag, key: .option, mode: .toggle))
        try check(!gate.permits(key: .option, mode: .toggle, flags: HoldKey.option.flag))
        try check(gate.permits(key: .option, mode: .held, flags: HoldKey.option.flag))
        gate.reset(flags: HoldKey.option.flag)
        try check(!gate.flagsChanged(HoldKey.option.flag, key: .option, mode: .toggle))
    }
    static func configuration() throws {
        try check(HoldKey.none.permits(flags: 0))
        try check(!HoldKey.option.permits(flags: HoldKey.shift.flag))
        try check(HoldKey.option.permits(flags: HoldKey.option.flag | HoldKey.command.flag))
        var settings = GestureSettings(); settings.top = .media; settings.bottom = .off
        try check(settings.action(for: .top) == .media && !settings.configuration.enabledEdges.contains(.bottom))
        settings.swapped = true
        try check(settings.action(for: .left) == .brightness && settings.action(for: .right) == .volume)
        try check(settings.action(for: .top) == .media)
    }
}
