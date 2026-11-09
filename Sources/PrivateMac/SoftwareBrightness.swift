import CoreGraphics
import GestureCore

public final class SoftwareBrightness {
    private struct Applied {
        let display: DisplayInfo
        let original: GammaTable
        let table: GammaTable
        let level: Double
    }

    // All state and display writes stay on the main queue so quit can restore
    // the curve after cancelling any queued brightness adjustments.
    private var applied: [CGDirectDisplayID: Applied] = [:]

    public init() {}

    public static func isAvailable(on display: CGDirectDisplayID) -> Bool {
        CGDisplayIsInMirrorSet(display) == 0 && GammaTable.read(display) != nil
    }

    public func adjust(on display: DisplayInfo, _ direction: Direction, step: Double,
                       whileValid: () -> Bool) throws -> LevelChange? {
        try SystemInput.onMain {
            guard whileValid() else { return nil }
            let id = display.id
            guard display.isCurrent, !display.builtIn, CGDisplayIsAsleep(id) == 0,
                  CGDisplayIsInMirrorSet(id) == 0, let live = GammaTable.read(id) else { throw Failure.unavailable }

            if let saved = applied[id], !saved.display.isCurrent || !live.matches(saved.table) {
                applied.removeValue(forKey: id)
            }
            let original = applied[id]?.original ?? live
            let current = applied[id]?.level ?? 1
            return try Adjustment.apply(.brightness, direction, step: step, read: { current }) { level in
                let table = original.scaled(by: Float(level))
                guard !table.matches(live), whileValid() else { return current }
                guard table.write(id) else { throw Failure.unavailable }
                applied[id] = level == 1 ? nil : Applied(display: display, original: original, table: table, level: level)
                guard let actual = GammaTable.read(id), actual.matches(table) else { throw Failure.unconfirmed }
                return level
            }
        }
    }

    public func restore(on id: CGDirectDisplayID) {
        SystemInput.onMain {
            guard let saved = applied[id] else { return }
            guard saved.display.isCurrent else { applied.removeValue(forKey: id); return }
            guard let current = GammaTable.read(id) else { return }
            // A profile change or another app may have replaced our curve.
            if !current.matches(saved.table) || saved.original.write(id) {
                applied.removeValue(forKey: id)
            }
        }
    }

    public func restore(except retained: Set<CGDirectDisplayID> = []) {
        SystemInput.onMain {
            for id in Array(applied.keys) where !retained.contains(id) { restore(on: id) }
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case unavailable, unconfirmed

        public var description: String {
            switch self {
            case .unavailable: return "이 화면의 소프트웨어 밝기를 조절할 수 없음"
            case .unconfirmed: return "화면 밝기 보정이 적용됐는지 확인할 수 없음"
            }
        }
    }
}

private struct GammaTable {
    let red: [CGGammaValue]
    let green: [CGGammaValue]
    let blue: [CGGammaValue]

    static func read(_ id: CGDirectDisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(id)
        guard capacity > 1 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &red, &green, &blue, &count) == .success,
              (2...capacity).contains(count) else { return nil }
        return GammaTable(red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))),
                          blue: Array(blue.prefix(Int(count))))
    }

    func write(_ id: CGDirectDisplayID) -> Bool {
        CGSetDisplayTransferByTable(id, UInt32(red.count), red, green, blue) == .success
    }

    func scaled(by factor: CGGammaValue) -> GammaTable {
        GammaTable(red: red.map { $0 * factor }, green: green.map { $0 * factor }, blue: blue.map { $0 * factor })
    }

    func matches(_ other: GammaTable) -> Bool {
        red.count == other.red.count && zip([red, green, blue], [other.red, other.green, other.blue]).allSatisfy { lhs, rhs in
            zip(lhs, rhs).allSatisfy { abs($0 - $1) <= 0.001 }
        }
    }
}
