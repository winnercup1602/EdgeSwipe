import CoreGraphics
import Foundation
import GestureCore
import PrivateMac

struct BrightnessScreen {
    enum Backend {
        case native(NativeBrightness)
        case direct(DDCBrightness?, confirmed: Bool, canDim: Bool)
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
            } else if !info.builtIn, let location = info.location, DDCBrightness.isDirectLocation(location) {
                let ddc = DDCBrightness(displayLocation: location)
                backend = .direct(ddc, confirmed: (try? ddc?.read()) != nil,
                                  canDim: SoftwareBrightness.isAvailable(on: id))
            } else {
                backend = .unavailable
            }
            result.append(BrightnessScreen(info: info, backend: backend))
        }
        guard whileValid(), result.contains(where: { !$0.info.builtIn && !$0.backlightReady }) else { return result }
        let linked = bridge.discover()
        return result.map { screen in
            guard !screen.info.builtIn, !screen.backlightReady,
                  let target = linked.first(where: { $0.displayID == screen.info.id && $0.name == screen.info.name }) else { return screen }
            return BrightnessScreen(info: screen.info, backend: .displayLink(bridge, target))
        }
    }

    private var backlightReady: Bool {
        switch backend {
        case .direct(_, let confirmed, _): return confirmed
        case .unavailable: return false
        default: return true
        }
    }

    var isDirect: Bool {
        if case .direct = backend { return true }
        return false
    }

    var handlesBrightnessKeys: Bool {
        guard case .direct(_, let confirmed, let canDim) = backend else { return false }
        return confirmed || canDim
    }

    var status: String {
        switch backend {
        case .native: return "내장 밝기 준비됨"
        case .direct(_, true, _): return "DDC/CI 준비됨"
        case .direct(_, false, let canDim): return canDim ? "소프트웨어 밝기 준비됨" : "DDC/CI 응답 없음"
        case .displayLink: return "DisplayLink 준비됨"
        case .unavailable: return "백라이트 제어 미지원"
        }
    }

    func target(software: SoftwareBrightness) throws -> ControlTarget {
        switch backend {
        case .native(let native): return .brightness(BuiltInBrightness(display: info.id, native: native))
        case .direct, .displayLink: return .external(ExternalBrightness(screen: self, software: software))
        case .unavailable: throw ControlFailure.displayUnavailable(info.name)
        }
    }
}

final class ExternalBrightness {
    let screen: BrightnessScreen
    private let software: SoftwareBrightness
    private var ddcReading: DDCBrightness.Reading?
    private var linkedLevel: Double?
    private var usesSoftware = false

    var confirmedDDC: Bool { !usesSoftware && ddcReading != nil }
    var feedbackDisplay: CGDirectDisplayID? {
        if case .displayLink = screen.backend { return screen.info.id }
        return nil
    }

    init(screen: BrightnessScreen, software: SoftwareBrightness) {
        self.screen = screen
        self.software = software
    }

    func adjust(_ direction: Direction, step: Double, whileValid: () -> Bool) throws -> LevelChange? {
        guard whileValid() else { throw ControlFailure.cancelled }
        let display = screen.info
        guard CGDisplayIsActive(display.id) != 0 else { throw ControlFailure.targetChanged }

        switch screen.backend {
        case .direct(let ddc, _, _):
            guard display.isCurrent, CGDisplayIsAsleep(display.id) == 0 else { throw ControlFailure.targetChanged }
            if let ddc, !usesSoftware {
                do {
                    return try adjustDDC(ddc, direction, step: step, whileValid: whileValid)
                } catch DDCBrightness.Failure.unavailable, DDCBrightness.Failure.unchanged {
                    usesSoftware = true
                } catch DDCBrightness.Failure.cancelled {
                    throw ControlFailure.cancelled
                }
            }
            return try software.adjust(on: display, direction, step: step, whileValid: whileValid)
        case .displayLink(let bridge, let target):
            let current = try linkedLevel ?? bridge.read(target)
            linkedLevel = current
            return try Adjustment.apply(.brightness, direction, step: step, read: { current }) { requested in
                guard whileValid() else { throw ControlFailure.cancelled }
                guard CGDisplayIsActive(display.id) != 0 else { throw ControlFailure.targetChanged }
                let actual = try bridge.write(requested, to: target)
                linkedLevel = actual
                return actual
            }
        default:
            throw ControlFailure.displayUnavailable(display.name)
        }
    }

    private func adjustDDC(_ ddc: DDCBrightness, _ direction: Direction, step: Double,
                           whileValid: () -> Bool) throws -> LevelChange? {
        let display = screen.info
        let previous = try ddcReading ?? ddc.read()
        ddcReading = previous
        let effectiveStep = max(step, 1 / Double(previous.maximum))
        let change = try Adjustment.apply(.brightness, direction, step: effectiveStep, read: { previous.level }) { requested in
            let actual = try ddc.write(requested, from: previous) {
                whileValid() && display.isCurrent && CGDisplayIsAsleep(display.id) == 0
            }
            ddcReading = actual
            return actual.level
        }
        if change != nil, whileValid() { software.restore(on: display.id) }
        return change
    }
}

final class DisplayControls {
    private struct KeyPress {
        let screen: BrightnessScreen
        let lease: OperationLease
    }

    private let native = NativeBrightness()
    private let bridge = DisplayLinkBrightness()
    private let software = SoftwareBrightness()
    private let queue: DispatchQueue
    private var scan: OperationLease?
    private var keyLease = OperationLease()
    private var pressedKeys: [Direction: KeyPress] = [:]
    private var pendingKeys = 0
    private(set) var screens: [CGDirectDisplayID: BrightnessScreen] = [:]
    private(set) var scanning = false
    var onChanged: () -> Void = {}
    var onAvailabilityChange: () -> Void = {}
    var onKeyAdjustment: (Error?) -> Void = { _ in }

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
                self.software.restore(except: Set(result.filter(\.isDirect).map { $0.info.id }))
                self.scanning = false
                self.onChanged()
            }
        }
    }

    func stop(restoreSoftware: Bool = false) {
        scan?.cancel()
        scan = nil
        cancelKeys()
        screens.removeAll()
        scanning = false
        if restoreSoftware { software.restore() }
    }

    func cancelKeys() {
        keyLease.cancel()
        keyLease = OperationLease()
    }

    func target(at point: CGPoint) throws -> ControlTarget {
        guard let id = DisplayInfo.id(at: point), let screen = screens[id] else {
            throw ControlFailure.displayUnavailable(scanning ? "화면 연결 확인 중" : "커서가 있는 화면")
        }
        return try screen.target(software: software)
    }

    func handleKey(_ key: DisplayBrightnessKey) -> Bool {
        let direction = key.direction
        switch key.phase {
        case .up:
            return pressedKeys.removeValue(forKey: direction) != nil
        case .repeating:
            guard let press = pressedKeys[direction] else { return false }
            if let step = key.step, pendingKeys == 0 { enqueueKey(direction, step: step, press: press) }
        case .down:
            pressedKeys.removeValue(forKey: direction)
            guard let step = key.step, let cursor = CGEvent(source: nil)?.location,
                  let id = DisplayInfo.id(at: cursor), let screen = screens[id],
                  screen.handlesBrightnessKeys else { return false }
            let press = KeyPress(screen: screen, lease: keyLease)
            pressedKeys[direction] = press
            enqueueKey(direction, step: step, press: press)
        }
        return true
    }

    private func enqueueKey(_ direction: Direction, step: Double, press: KeyPress) {
        guard press.lease.valid else { return }
        pendingKeys += 1
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result {
                let target = try press.screen.target(software: self.software)
                _ = try target.adjust(direction, step: step) { press.lease.valid }
                return target
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingKeys -= 1
                guard press.lease.valid else { return }
                switch result {
                case .success(let target):
                    if case .external(let external) = target, self.updatePath(for: external) { self.onChanged() }
                    self.onKeyAdjustment(nil)
                case .failure(let error):
                    self.onKeyAdjustment(error)
                }
            }
        }
    }

    func updatePath(for target: ExternalBrightness) -> Bool {
        let id = target.screen.info.id
        guard case .direct(let ddc, _, _) = target.screen.backend, let current = screens[id],
              case .direct(let active, let confirmed, let canDim) = current.backend, active === ddc,
              current.info.isCurrent, confirmed != target.confirmedDDC else { return false }
        screens[id] = BrightnessScreen(info: current.info,
                                       backend: .direct(ddc, confirmed: target.confirmedDDC, canDim: canDim))
        return true
    }
}
