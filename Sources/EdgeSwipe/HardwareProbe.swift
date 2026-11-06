#if DEBUG
import ApplicationServices
import AppKit
import Foundation
import GestureCore
import PrivateMac
import os

func runHardwareProbe(roundTrip: Bool) -> Int32 {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled],
                                                        reason: "Verify EdgeSwipe hardware controls")
    defer { ProcessInfo.processInfo.endActivity(activity) }
    var failures = 0
    let trackpads = Trackpads()
    var frames: [UInt64: Int] = [:]
    trackpads.onFrame = { id, _ in frames[id, default: 0] += 1 }
    trackpads.start()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    let pads = trackpads.status
    print("Trackpad API: \(trackpads.available), registered \(pads.count)/\(trackpads.detectedCount)")
    if pads.isEmpty || pads.count != trackpads.detectedCount { failures += 1 }
    for pad in pads {
        let feedback = pad.hapticsAvailable ? "opened" : "unavailable"
        print("\(pad.name): actuator \(feedback), \(frames[pad.id, default: 0]) callback frames")
        if !pad.hapticsAvailable { failures += 1 }
    }
    trackpads.stop()

    let hardwareResult = OSAllocatedUnfairLock(initialState: 0)
    let done = DispatchGroup()
    done.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        let errors = probeControls(roundTrip: roundTrip)
        hardwareResult.withLock { $0 = errors }
        done.leave()
    }
    while done.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    failures += hardwareResult.withLock { $0 }
    print("Accessibility for this process: \(AXIsProcessTrusted())")
    return failures == 0 ? 0 : 1
}

private func probeControls(roundTrip: Bool) -> Int {
    var failures = 0

    do {
        let audio = try AudioOutput.current()
        let current = try audio.read()
        print("volume read: \(current)")
        if roundTrip, current > 0 {
            try checkRoundTrip("volume", original: current, readFresh: audio.read,
                               adjust: { try ControlTarget.volume(audio).adjust($0, whileValid: { true }) },
                               restore: audio.write)
        }
    } catch {
        print("volume probe failed: \(error)")
        failures += 1
    }

    do {
        guard let display = BuiltInDisplay.activeID, let native = NativeBrightness() else {
            print("brightness probe requires a MacBook with its built-in display only")
            return failures + 1
        }
        let brightness = BuiltInBrightness(display: display, native: native)
        let current = try brightness.read()
        print("MacBook brightness read: \(current)")
        let onKeyStep = abs(current / Control.stepSize - (current / Control.stepSize).rounded()) < 0.0016
        if roundTrip, current >= Control.brightness.minimum, onKeyStep {
            try checkRoundTrip("brightness", original: current, readFresh: brightness.read,
                               adjust: { try brightness.adjust($0, whileValid: { true }) },
                               restore: { try restoreBrightness($0, using: brightness) })
            try checkBrightnessCancellation(brightness)
        } else if roundTrip {
            print("brightness round-trip requires an initial system keyboard step")
        }
    } catch {
        print("brightness probe failed: \(error)")
        failures += 1
    }
    return failures
}

private func restoreBrightness(_ original: Double, using brightness: BuiltInBrightness) throws {
    let actual = try brightness.read()
    guard abs(actual - original) > 0.0001 else { return }
    guard abs(actual - original) <= Control.stepSize + 0.012 else { throw ControlFailure.targetChanged }
    let direction: Direction = actual < original ? .up : .down
    guard try brightness.adjust(direction, whileValid: { true }) != nil else {
        throw ControlFailure.brightnessKeyUnconfirmed
    }
}

private func checkBrightnessCancellation(_ brightness: BuiltInBrightness) throws {
    let original = try brightness.read()
    let direction: Direction = original >= 0.5 ? .down : .up
    var checks = 0
    let result = Result {
        try brightness.adjust(direction) {
            checks += 1
            return checks == 1
        }
    }
    // An accepted key can finish after cancellation. Let it arrive before
    // restoring through the same keyboard path used by the app.
    Thread.sleep(forTimeInterval: 0.3)
    try restoreBrightness(original, using: brightness)
    guard abs(try brightness.read() - original) <= 0.0001 else { throw ControlFailure.system(-1) }
    guard case .failure(ControlFailure.cancelled) = result else { throw ControlFailure.system(-1) }
    print("brightness cancellation after accepted input: confirmed")
}

private func checkRoundTrip(
    _ name: String, original: Double, readFresh: () throws -> Double,
    adjust: (Direction) throws -> LevelChange?, restore: (Double) throws -> Void
) throws {
    let direction: Direction = original >= 0.5 ? .down : .up
    let check = Result {
        guard let step = try adjust(direction) else {
            throw ControlFailure.system(-1)
        }
        Thread.sleep(forTimeInterval: 0.18)
        let actual = try readFresh()
        print("\(name) step: \(actual) (confirmed target \(step.level))")
        guard abs(actual - step.level) <= 0.04 else { throw ControlFailure.system(-1) }
    }
    try restore(original)
    Thread.sleep(forTimeInterval: 0.18)
    let restored = try readFresh()
    print("\(name) restored: \(restored)")
    guard abs(restored - original) <= 0.0001 else { throw ControlFailure.system(-1) }
    try check.get()
}
#endif
