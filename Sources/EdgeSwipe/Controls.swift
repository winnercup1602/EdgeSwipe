import AudioToolbox
import CoreAudio
import CoreGraphics
import GestureCore
import PrivateMac

enum ControlFailure: Error, CustomStringConvertible {
    case audioUnavailable
    case displayUnavailable(String)
    case brightnessFeedbackUnavailable
    case targetChanged
    case cancelled
    case system(OSStatus)

    var description: String {
        switch self {
        case .audioUnavailable: return "기본 출력 장치의 볼륨을 조절할 수 없음"
        case .displayUnavailable(let name): return "\(name) 백라이트 경로 없음"
        case .brightnessFeedbackUnavailable: return "macOS 밝기 변경 표시를 열 수 없음"
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

struct BrightnessScreen {
    enum Backend {
        case native(NativeBrightness)
        case ddc(DDCBrightness)
        case displayLink(DisplayLinkBrightness, DisplayLinkBrightness.Screen)
        case unavailable
    }

    let info: DisplayInfo
    let backend: Backend

    private init(id: CGDirectDisplayID, native: NativeBrightness?) {
        let info = DisplayInfo(id: id)
        self.info = info
        if info.builtIn, let native, (try? native.read(display: id)) != nil {
            backend = .native(native)
        } else if let location = info.location,
                  let ddc = DDCBrightness(displayLocation: location), (try? ddc.read()) != nil {
            backend = .ddc(ddc)
        } else {
            backend = .unavailable
        }
    }

    private init(info: DisplayInfo, backend: Backend) {
        self.info = info
        self.backend = backend
    }

    static func detect(
        native: NativeBrightness?, displayLink: DisplayLinkBrightness, continuing: () -> Bool = { true }
    ) -> [BrightnessScreen] {
        var detected: [BrightnessScreen] = []
        for id in DisplayInfo.activeIDs() {
            guard continuing() else { return [] }
            detected.append(BrightnessScreen(id: id, native: native))
        }
        guard detected.contains(where: { !$0.info.builtIn && !$0.supported }), continuing() else { return detected }
        let linked = displayLink.discover()
        return detected.map { screen in
            guard !screen.info.builtIn, !screen.supported,
                  let target = linked.first(where: {
                      $0.displayID == screen.info.id && $0.name == screen.info.name
                  }) else { return screen }
            return BrightnessScreen(info: screen.info, backend: .displayLink(displayLink, target))
        }
    }

    var status: String {
        switch backend {
        case .native: return "내장 밝기 준비됨"
        case .ddc: return "DDC/CI 백라이트 준비됨"
        case .displayLink: return "DisplayLink 백라이트 준비됨"
        case .unavailable: return "백라이트 경로 없음"
        }
    }

    var supported: Bool {
        if case .unavailable = backend { return false }
        return true
    }
}

// The serial control queue owns the sample cache. Each gesture reads fresh
// hardware state once and keeps the most recent verified DDC write thereafter.
final class BrightnessStroke {
    private let screen: BrightnessScreen
    private var sample: DDCBrightness.Reading?
    private var linkedLevel: Double?

    init(screen: BrightnessScreen) {
        self.screen = screen
    }

    var displayID: CGDirectDisplayID { screen.info.id }

    func read() throws -> Double {
        guard CGDisplayIsActive(screen.info.id) != 0 else { throw ControlFailure.targetChanged }
        switch screen.backend {
        case .native(let native):
            return try native.read(display: screen.info.id)
        case .ddc(let ddc):
            if let sample { return sample.level }
            let current = try ddc.read()
            sample = current
            return current.level
        case let .displayLink(bridge, target):
            if let linkedLevel { return linkedLevel }
            let level = try bridge.read(target)
            linkedLevel = level
            return level
        case .unavailable:
            throw ControlFailure.displayUnavailable(screen.info.name)
        }
    }

    func write(_ level: Double) throws -> Double {
        guard CGDisplayIsActive(screen.info.id) != 0 else { throw ControlFailure.targetChanged }
        switch screen.backend {
        case .native(let native):
            try native.write(level, display: screen.info.id)
            return try native.read(display: screen.info.id)
        case .ddc(let ddc):
            let previous = try sample ?? ddc.read()
            let actual = try ddc.write(level, from: previous)
            sample = actual
            return actual.level
        case let .displayLink(bridge, target):
            let actual = try bridge.write(level, to: target)
            linkedLevel = actual
            return actual
        case .unavailable:
            throw ControlFailure.displayUnavailable(screen.info.name)
        }
    }

    func adjust(_ direction: Direction, whileValid: () -> Bool) throws -> LevelChange? {
        let current = try read()
        return try Adjustment.apply(.brightness, direction, read: { current }) { level in
            guard whileValid() else { throw ControlFailure.cancelled }
            return try write(level)
        }
    }
}

enum ControlTarget {
    case volume(AudioOutput)
    case brightness(BrightnessStroke)

    var feedbackDisplay: CGDirectDisplayID? {
        guard case .brightness(let stroke) = self else { return nil }
        return stroke.displayID
    }

    func adjust(_ direction: Direction, whileValid: () -> Bool) throws -> LevelChange? {
        switch self {
        case .volume(let audio):
            return try Adjustment.apply(.volume, direction, read: audio.read) { level in
                guard whileValid() else { throw ControlFailure.cancelled }
                try audio.write(level)
                return level
            }
        case .brightness(let stroke):
            return try stroke.adjust(direction, whileValid: whileValid)
        }
    }
}
