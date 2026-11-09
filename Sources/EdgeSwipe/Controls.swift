import AudioToolbox
import CoreAudio
import CoreGraphics
import GestureCore
import PrivateMac

enum ControlFailure: Error, CustomStringConvertible {
    case audioUnavailable
    case volumeKeyUnconfirmed
    case inputUnavailable
    case displayUnavailable(String)
    case keyboardUnavailable
    case brightnessKeyUnavailable
    case brightnessKeyUnconfirmed
    case targetChanged
    case cancelled
    case system(OSStatus)

    var description: String {
        switch self {
        case .inputUnavailable: return "시스템 입력을 보낼 수 없음 · 권한 확인"
        case .displayUnavailable(let name): return "\(name) 백라이트 경로 없음"
        case .keyboardUnavailable: return "키보드 백라이트를 사용할 수 없음"
        case .audioUnavailable: return "기본 출력 장치의 볼륨을 조절할 수 없음"
        case .volumeKeyUnconfirmed: return "시스템 볼륨 키 입력 후 변경을 확인하지 못함"
        case .brightnessKeyUnavailable: return "밝기 키 입력을 사용할 수 없음 · 손쉬운 사용 권한 확인"
        case .brightnessKeyUnconfirmed: return "시스템 밝기 키 입력 후 변경을 확인하지 못함"
        case .targetChanged: return "조절 대상이 바뀜"
        case .cancelled: return "조절 취소됨"
        case .system(let status): return "시스템 호출 실패 (\(status))"
        }
    }
}

struct AudioOutput {
    private let id: AudioDeviceID
    private let volumeSelector: AudioObjectPropertySelector
    private let canSetMute: Bool

    static func current() throws -> AudioOutput {
        let id = try defaultID()
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar]
        where settable(id, selector) {
            let output = AudioOutput(id: id, volumeSelector: selector,
                                     canSetMute: settable(id, kAudioDevicePropertyMute))
            if (try? output.rawVolume()) != nil { return output }
        }
        throw ControlFailure.audioUnavailable
    }

    func read() throws -> Double {
        guard try Self.defaultID() == id else { throw ControlFailure.targetChanged }
        if canSetMute, try isMuted() { return 0 }
        return Double(try rawVolume())
    }

    func adjust(_ direction: Direction, step: Double, whileValid: () -> Bool) throws -> LevelChange? {
        let current = try read()
        return try Adjustment.apply(.volume, direction, step: step, read: { current }) { _ in
            let key: SystemInput.MediaKey = direction == .up ? .volumeUp : .volumeDown
            guard SystemInput.media(key, precise: step < Control.stepSize, whileValid: {
                whileValid() && (try? Self.defaultID()) == id
            }) else {
                guard whileValid() else { throw ControlFailure.cancelled }
                guard try Self.defaultID() == id else { throw ControlFailure.targetChanged }
                throw ControlFailure.inputUnavailable
            }
            return try waitForSystemLevel(whileValid: whileValid, failure: .volumeKeyUnconfirmed) {
                let actual = try read()
                return (actual - current) * Double(direction.rawValue) > 0.000_01 ? actual : nil
            }
        }
    }

    func write(_ level: Double) throws {
        guard try Self.defaultID() == id else { throw ControlFailure.targetChanged }
        let wasMuted = canSetMute ? try isMuted() : false
        let oldLevel = wasMuted ? try rawVolume() : 0
        try set(volumeSelector, Float32(level))
        guard wasMuted else { return }
        do {
            if try isMuted() { try set(kAudioDevicePropertyMute, UInt32(0)) }
        } catch {
            try? set(volumeSelector, oldLevel)
            try? set(kAudioDevicePropertyMute, UInt32(1))
            throw error
        }
    }

    func toggleMute(previous: inout [UInt32: Double]) throws -> Double {
        guard try Self.defaultID() == id else { throw ControlFailure.targetChanged }
        if canSetMute {
            let muted = try isMuted()
            try set(kAudioDevicePropertyMute, UInt32(muted ? 0 : 1))
            guard try isMuted() != muted else { throw ControlFailure.audioUnavailable }
            return muted ? Double(try rawVolume()) : 0
        }
        let current = try read()
        if current > 0 { previous[id] = current; try write(0); return 0 }
        let restored = previous[id] ?? 0.5
        try write(restored)
        return try read()
    }

    private func rawVolume() throws -> Float32 {
        try Self.get(id, volumeSelector, kAudioObjectPropertyScopeOutput, Float32(0))
    }

    private func isMuted() throws -> Bool {
        try Self.get(id, kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, UInt32(0)) != 0
    }

    private static func defaultID() throws -> AudioDeviceID {
        let id = try get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioObjectPropertyScopeGlobal, AudioDeviceID(kAudioObjectUnknown))
        guard id != kAudioObjectUnknown else { throw ControlFailure.audioUnavailable }
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func settable(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
        var addr = address(selector, kAudioObjectPropertyScopeOutput)
        var result: DarwinBoolean = false
        return AudioObjectHasProperty(id, &addr)
            && AudioObjectIsPropertySettable(id, &addr, &result) == noErr && result.boolValue
    }

    private static func get<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               _ scope: AudioObjectPropertyScope, _ initial: T) throws -> T {
        var addr = address(selector, scope)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { throw ControlFailure.system(status) }
        return value
    }

    private func set<T>(_ selector: AudioObjectPropertySelector, _ value: T) throws {
        var addr = Self.address(selector, kAudioObjectPropertyScopeOutput)
        let status = withUnsafeBytes(of: value) { bytes in
            AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(bytes.count), bytes.baseAddress!)
        }
        guard status == noErr else { throw ControlFailure.system(status) }
    }
}

struct BuiltInBrightness {
    let display: CGDirectDisplayID
    let native: NativeBrightness

    func read() throws -> Double {
        guard BuiltInDisplay.activeID == display else { throw ControlFailure.targetChanged }
        return try native.read(display: display)
    }

    func adjust(_ direction: Direction, step: Double = Control.stepSize, whileValid: () -> Bool) throws -> LevelChange? {
        let current = try read()
        return try Adjustment.apply(.brightness, direction, step: step, read: { current }) { _ in
            guard NativeBrightnessKeys.post(increase: direction == .up, on: display, precise: step < Control.stepSize,
                                            whileValid: whileValid) else {
                guard whileValid() else { throw ControlFailure.cancelled }
                guard BuiltInDisplay.activeID == display else { throw ControlFailure.targetChanged }
                throw ControlFailure.brightnessKeyUnavailable
            }
            return try confirmSystemKey(from: current, direction: direction, step: step, whileValid: whileValid)
        }
    }

    private func confirmSystemKey(from current: Double, direction: Direction, step: Double,
                                  whileValid: () -> Bool) throws -> Double {
        try waitForSystemLevel(whileValid: whileValid, failure: .brightnessKeyUnconfirmed) {
            guard BuiltInDisplay.activeID == display else { throw ControlFailure.targetChanged }
            guard let actual = try? native.read(display: display) else { return nil }
            let delta = (actual - current) * Double(direction.rawValue)
            guard delta > 0.001, delta <= step + (step < Control.stepSize ? 0.003 : 0.012),
                  actual >= Control.brightness.minimum - 0.0001 else { return nil }
            return actual
        }
    }
}

private func waitForSystemLevel(whileValid: () -> Bool, failure: ControlFailure,
                                readConfirmedLevel: () throws -> Double?) throws -> Double {
    for _ in 0..<12 {
        Thread.sleep(forTimeInterval: 0.02)
        guard whileValid() else { throw ControlFailure.cancelled }
        if let level = try readConfirmedLevel() { return level }
    }
    throw failure
}

enum ControlTarget {
    case volume(AudioOutput)
    case brightness(BuiltInBrightness)
    case external(ExternalBrightness)
    case keyboard(KeyboardBrightness)

    var feedbackDisplay: CGDirectDisplayID? {
        if case .external(let target) = self { return target.feedbackDisplay }
        return nil
    }

    func adjust(_ direction: Direction, step: Double = Control.stepSize, whileValid: () -> Bool) throws -> LevelChange? {
        switch self {
        case .volume(let audio):
            return try audio.adjust(direction, step: step, whileValid: whileValid)
        case .brightness(let brightness):
            return try brightness.adjust(direction, step: step, whileValid: whileValid)
        case .external(let target):
            return try target.adjust(direction, step: step, whileValid: whileValid)
        case .keyboard(let keyboard):
            return try Adjustment.apply(.keyboardBrightness, direction, step: step, read: keyboard.read) { level in
                guard whileValid() else { throw ControlFailure.cancelled }
                return try keyboard.write(level)
            }
        }
    }
}
