import Foundation

public struct Finger: Equatable, Sendable {
    public let id: Int32
    public let x: Double
    public let y: Double
    public let size: Double
    public let majorAxis: Double
    public init(id: Int32, x: Double, y: Double, size: Double = 0, majorAxis: Double = 0) {
        self.id = id; self.x = x; self.y = y; self.size = size; self.majorAxis = majorAxis
    }
    public var valid: Bool { x.isFinite && y.isFinite && size.isFinite && majorAxis.isFinite && size >= 0 && majorAxis >= 0 && (0...1).contains(x) && (0...1).contains(y) }
    // Conservatively reject broad contacts before recognizing an edge or tap.
    // Hardware acceptance also checks the shape thresholds on each trackpad.
    public var palm: Bool { size > 2.5 || majorAxis > 18 }
}

public enum TapAction: Equatable, Sendable {
    case middleClick, playPause, corner(CornerAction)
}

public struct TapGesture {
    public private(set) var consumesClick = false
    private var start: [Int32: Finger] = [:]
    private var firstTime = 0.0
    private var maximumCount = 0
    private var blocked = false
    private var pendingCorner: (Corner, Double)?
    public init() {}

    public mutating func cancel() { blocked = true; start.removeAll(); pendingCorner = nil }

    public mutating func update(_ fingers: [Finger], at time: Double, settings: GestureSettings) -> TapAction? {
        consumesClick = false
        if fingers.isEmpty {
            defer { start.removeAll(); blocked = false; maximumCount = 0 }
            guard !blocked, !start.isEmpty, time - firstTime <= 0.28 else { return nil }
            if maximumCount == 3, settings.threeFingerClick { consumesClick = true; pendingCorner = nil; return .middleClick }
            guard maximumCount == 1, let finger = start.values.first else { return nil }
            if let corner = Corner.at(x: finger.x, y: finger.y, width: max(0.08, settings.width.fraction)),
               let action = settings.corners[corner], action != .off {
                consumesClick = true
                if let previous = pendingCorner, previous.0 == corner, (0...0.35).contains(time - previous.1) {
                    pendingCorner = nil
                    return .corner(action)
                }
                pendingCorner = (corner, time)
                return nil
            }
            pendingCorner = nil
            if settings.bottom == .media, finger.y <= settings.width.fraction { consumesClick = true; return .playPause }
            if settings.top == .media, finger.y >= 1 - settings.width.fraction { consumesClick = true; return .playPause }
            return nil
        }
        guard !blocked, fingers.count <= 3, fingers.allSatisfy({ $0.valid && !$0.palm }) else { cancel(); return nil }
        if start.isEmpty { firstTime = time }
        maximumCount = max(maximumCount, fingers.count)
        if maximumCount == 2 && fingers.count < 2 { cancel(); return nil }
        for finger in fingers {
            if let origin = start[finger.id] {
                if hypot(finger.x - origin.x, finger.y - origin.y) > 0.018 { cancel(); return nil }
            } else {
                guard time - firstTime < 0.10 else { cancel(); return nil }
                start[finger.id] = finger
            }
        }
        if start.count > 3 || (maximumCount == 1 && start.count > 1) || time - firstTime > 0.28 { cancel() }
        return nil
    }
}
