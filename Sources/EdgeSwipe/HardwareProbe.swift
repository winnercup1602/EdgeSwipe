#if DEBUG
import ApplicationServices
import CoreGraphics
import Foundation
import GestureCore
import PrivateMac
import os

func runHardwareProbe(roundTrip: Bool) -> Int32 {
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

    let manager = DisplayLinkBrightness()
    let hardwareResult = OSAllocatedUnfairLock(initialState: 0)
    let done = DispatchGroup()
    done.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        let errors = probeControls(manager: manager, roundTrip: roundTrip)
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

private func probeControls(manager: DisplayLinkBrightness, roundTrip: Bool) -> Int {
    var failures = 0
    let native = NativeBrightness()
    let screens = BrightnessScreen.detect(native: native, displayLink: manager)
    for screen in screens {
        let bounds = CGDisplayBounds(screen.info.id)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let selected = DisplayInfo.id(at: center) == screen.info.id
        print("\(screen.info.name): \(screen.status), cursor target \(selected ? "confirmed" : "ambiguous")")
        if !selected { failures += 1 }
    }

    do {
        let audio = try AudioOutput.current()
        let current = try audio.read()
        print("volume read: \(current)")
        if roundTrip, current > 0 {
            try checkRoundTrip("volume", control: .volume, original: current, readFresh: audio.read) { level in
                try audio.write(level)
                return level
            }
        }
    } catch {
        print("volume probe failed: \(error)")
        failures += 1
    }

    let supported = screens.filter(\.supported)
    for screen in supported {
        do {
            let readFresh = { try BrightnessStroke(screen: screen).read() }
            let current = try readFresh()
            print("\(screen.info.name) brightness read: \(current)")
            if roundTrip {
                let peers = supported.filter { $0.info.id != screen.info.id }
                let before = try peers.map { try BrightnessStroke(screen: $0).read() }
                try checkRoundTrip(screen.info.name, control: .brightness, original: current,
                                   readFresh: readFresh,
                                   write: { try BrightnessStroke(screen: screen).write($0) }) {
                    for (peer, level) in zip(peers, before) {
                        guard abs(try BrightnessStroke(screen: peer).read() - level) < 0.0001 else {
                            throw ControlFailure.targetChanged
                        }
                        print("  \(peer.info.name) stayed at \(level)")
                    }
                }
            }
        } catch {
            print("\(screen.info.name) probe failed: \(error)")
            failures += 1
        }
    }
    return failures
}

private func checkRoundTrip(
    _ name: String, control: Control, original: Double,
    readFresh: () throws -> Double, write: (Double) throws -> Double,
    checkPeers: () throws -> Void = {}
) throws {
    let direction: Direction = original >= 0.5 ? .down : .up
    let check = Result {
        guard let step = try Adjustment.apply(control, direction, read: { original }, write: write) else {
            throw ControlFailure.system(-1)
        }
        Thread.sleep(forTimeInterval: 0.18)
        let actual = try readFresh()
        print("\(name) step: \(actual) (confirmed target \(step.level))")
        guard abs(actual - step.level) <= 0.04 else { throw ControlFailure.system(-1) }
        try checkPeers()
    }
    _ = try write(original)
    Thread.sleep(forTimeInterval: 0.18)
    let restored = try readFresh()
    print("\(name) restored: \(restored)")
    guard abs(restored - original) <= 0.0001 else { throw ControlFailure.system(-1) }
    try check.get()
}
#endif
