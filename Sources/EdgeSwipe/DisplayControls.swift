import CoreGraphics
import Foundation
import GestureCore
import PrivateMac

struct BrightnessScreen {
    enum Backend {
        case native(NativeBrightness)
        case ddc(DDCBrightness)
        case displayLink(DisplayLinkBrightness, DisplayLinkBrightness.Screen)
        case unavailable
    }
    let info: DisplayInfo
    let backend: Backend

    static func detect(native: NativeBrightness?, bridge: DisplayLinkBrightness,
                       whileValid: () -> Bool) -> [BrightnessScreen] {
        var result: [BrightnessScreen] = []
        for id in DisplayInfo.activeIDs() {
            guard whileValid() else { return [] }
            let info = DisplayInfo(id: id)
            let backend: Backend
            if info.builtIn, let native, (try? native.read(display: id)) != nil {
                backend = .native(native)
            } else if !info.builtIn, let location = info.location,
                      let ddc = DDCBrightness(displayLocation: location), (try? ddc.read()) != nil {
                backend = .ddc(ddc)
            } else { backend = .unavailable }
            result.append(BrightnessScreen(info: info, backend: backend))
        }
        guard whileValid(), result.contains(where: { !$0.info.builtIn && !$0.supported }) else { return result }
        let linked = bridge.discover()
        return result.map { screen in
            guard !screen.info.builtIn, !screen.supported,
                  let target = linked.first(where: { $0.displayID == screen.info.id && $0.name == screen.info.name }) else { return screen }
            return BrightnessScreen(info: screen.info, backend: .displayLink(bridge, target))
        }
    }

    var supported: Bool { if case .unavailable = backend { return false }; return true }
    var status: String {
        switch backend {
        case .native: return "내장 밝기 준비됨"
        case .ddc: return "DDC/CI 준비됨"
        case .displayLink: return "DisplayLink 준비됨"
        case .unavailable: return "백라이트 제어 미지원"
        }
    }

    func target() throws -> ControlTarget {
        switch backend {
        case .native(let native): return .brightness(BuiltInBrightness(display: info.id, native: native))
        case .ddc, .displayLink: return .external(ExternalBrightness(screen: self))
        case .unavailable: throw ControlFailure.displayUnavailable(info.name)
        }
    }
}

final class ExternalBrightness {
    let screen: BrightnessScreen
    private var ddcReading: DDCBrightness.Reading?
    private var linkedLevel: Double?

    init(screen: BrightnessScreen) { self.screen = screen }

    private func read() throws -> Double {
        guard CGDisplayIsActive(screen.info.id) != 0 else { throw ControlFailure.targetChanged }
        switch screen.backend {
        case .ddc(let ddc):
            if ddcReading == nil { ddcReading = try ddc.read() }
            return ddcReading!.level
        case .displayLink(let bridge, let target):
            if linkedLevel == nil { linkedLevel = try bridge.read(target) }
            return linkedLevel!
        default: throw ControlFailure.displayUnavailable(screen.info.name)
        }
    }

    func adjust(_ direction: Direction, step: Double, whileValid: () -> Bool) throws -> LevelChange? {
        let current = try read()
        let effectiveStep = max(step, ddcReading.map { 1.0 / Double($0.maximum) } ?? step)
        return try Adjustment.apply(.brightness, direction, step: effectiveStep, read: { current }) { requested in
            guard whileValid() else { throw ControlFailure.cancelled }
            guard CGDisplayIsActive(screen.info.id) != 0 else { throw ControlFailure.targetChanged }
            switch screen.backend {
            case .ddc(let ddc):
                let previous = try ddcReading ?? ddc.read()
                let actual = try ddc.write(requested, from: previous)
                ddcReading = actual
                return actual.level
            case .displayLink(let bridge, let target):
                let actual = try bridge.write(requested, to: target)
                linkedLevel = actual
                return actual
            default: throw ControlFailure.displayUnavailable(screen.info.name)
            }
        }
    }
}

final class DisplayControls {
    private let native = NativeBrightness()
    private let bridge = DisplayLinkBrightness()
    private let queue: DispatchQueue
    private var scan: OperationLease?
    private(set) var screens: [CGDirectDisplayID: BrightnessScreen] = [:]
    private(set) var scanning = false
    var onChanged: () -> Void = {}
    var onAvailabilityChange: () -> Void = {}

    init(queue: DispatchQueue) {
        self.queue = queue
        bridge.onAvailabilityChange = { [weak self] in self?.onAvailabilityChange() }
    }

    func refresh() {
        stop()
        let lease = OperationLease()
        scan = lease
        scanning = true
        onChanged()
        queue.async { [weak self] in
            guard let self, lease.valid else { return }
            let result = BrightnessScreen.detect(native: self.native, bridge: self.bridge, whileValid: { lease.valid })
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scan === lease, lease.valid else { return }
                self.screens = Dictionary(uniqueKeysWithValues: result.map { ($0.info.id, $0) })
                self.scanning = false
                self.onChanged()
            }
        }
    }

    func stop() {
        scan?.cancel()
        scan = nil
        screens.removeAll()
        scanning = false
    }

    func target(at point: CGPoint) throws -> ControlTarget {
        guard let id = DisplayInfo.id(at: point), let screen = screens[id] else {
            throw ControlFailure.displayUnavailable(scanning ? "화면 연결 확인 중" : "커서가 있는 화면")
        }
        return try screen.target()
    }
}
