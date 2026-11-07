import Foundation

public enum GestureAction: String, CaseIterable, Sendable {
    case volume, brightness, switchApps, scrubVideo, keyboardBrightness, media, off
    public var title: String {
        switch self {
        case .volume: return "볼륨"
        case .brightness: return "화면 밝기"
        case .switchApps: return "앱 전환"
        case .scrubVideo: return "동영상 탐색"
        case .keyboardBrightness: return "키보드 밝기"
        case .media: return "미디어"
        case .off: return "사용 안 함"
        }
    }
}

public enum EdgeWidth: String, CaseIterable, Sendable {
    case narrow, standard, wide
    public var fraction: Double { self == .narrow ? 0.03 : self == .wide ? 0.08 : 0.05 }
    public var title: String { self == .narrow ? "좁게" : self == .wide ? "넓게" : "보통" }
}

public enum HapticStrength: String, CaseIterable, Sendable {
    case off, light, medium, strong
    public var title: String {
        switch self { case .off: return "끔"; case .light: return "약하게"; case .medium: return "보통"; case .strong: return "강하게" }
    }
    public func gain(level: Double) -> Float {
        guard self != .off else { return 0 }
        let span: Double = self == .light ? 0.25 : self == .strong ? 0.74 : 0.58
        return Float(0.22 + span * min(1, max(0, level)))
    }
}

public enum HoldKey: String, CaseIterable, Sendable {
    case none, option, control, shift, command, function
    public var title: String {
        switch self { case .none: return "없음"; case .option: return "⌥ Option"; case .control: return "⌃ Control"; case .shift: return "⇧ Shift"; case .command: return "⌘ Command"; case .function: return "fn" }
    }
    public var flag: UInt64 {
        switch self { case .none: return 0; case .option: return 1 << 19; case .control: return 1 << 18; case .shift: return 1 << 17; case .command: return 1 << 20; case .function: return 1 << 23 }
    }
    public func permits(flags: UInt64) -> Bool { self == .none || flags & flag != 0 }
}

public enum HoldMode: String, CaseIterable, Sendable {
    case held, toggle
    public var title: String { self == .held ? "누른 동안" : "한 번 눌러 켜기·끄기" }
}

public struct HoldGate {
    public private(set) var latched = false
    private var previousFlags: UInt64 = 0
    public init() {}
    public mutating func reset(flags: UInt64 = 0) { latched = false; previousFlags = flags }
    @discardableResult
    public mutating func flagsChanged(_ flags: UInt64, key: HoldKey, mode: HoldMode) -> Bool {
        defer { previousFlags = flags }
        guard key != .none, mode == .toggle, flags & key.flag != 0, previousFlags & key.flag == 0 else { return false }
        latched.toggle()
        return true
    }
    public func permits(key: HoldKey, mode: HoldMode, flags: UInt64) -> Bool {
        key == .none || (mode == .toggle ? latched : key.permits(flags: flags))
    }
}

public enum Corner: String, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    public var title: String {
        switch self { case .topLeft: return "왼쪽 위"; case .topRight: return "오른쪽 위"; case .bottomLeft: return "왼쪽 아래"; case .bottomRight: return "오른쪽 아래" }
    }
    public static func at(x: Double, y: Double, width: Double) -> Corner? {
        if x <= width { return y <= width ? .bottomLeft : y >= 1 - width ? .topLeft : nil }
        if x >= 1 - width { return y <= width ? .bottomRight : y >= 1 - width ? .topRight : nil }
        return nil
    }
}

public enum CornerAction: String, CaseIterable, Sendable {
    case off, mute, screenshot
    public var title: String { self == .off ? "사용 안 함" : self == .mute ? "음소거 전환" : "스크린샷 도구 막대" }
}

public struct GestureConfiguration: Sendable {
    public var width: EdgeWidth = .standard
    public var bottomQuarterOnly = false
    public var enabledEdges: Set<Edge> = [.left, .right]
    public var singleFingerDelay = 0.055
    public init() {}
}

public struct GestureSettings: Sendable {
    public var swapped = false
    public var precise = false
    public var freezeCursor = true
    public var bottomQuarterOnly = false
    public var threeFingerClick = false
    public var width = EdgeWidth.standard
    public var haptics = HapticStrength.medium
    public var holdKey = HoldKey.none
    public var holdMode = HoldMode.held
    public var top = GestureAction.switchApps
    public var bottom = GestureAction.keyboardBrightness
    public var corners: [Corner: CornerAction] = Dictionary(uniqueKeysWithValues: Corner.allCases.map { ($0, .off) })
    public init() {}
    public var step: Double { precise ? 1.0 / 64 : Control.stepSize }
    public func action(for edge: Edge) -> GestureAction {
        switch edge {
        case .left: return swapped ? .brightness : .volume
        case .right: return swapped ? .volume : .brightness
        case .top: return top
        case .bottom: return bottom
        }
    }
    public var configuration: GestureConfiguration {
        var result = GestureConfiguration()
        result.width = width
        result.bottomQuarterOnly = bottomQuarterOnly
        result.enabledEdges = Set(Edge.allCases.filter { action(for: $0) != .off })
        return result
    }
}
