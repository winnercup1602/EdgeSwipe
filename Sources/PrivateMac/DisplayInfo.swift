import CoreGraphics
import Darwin
import Foundation

public struct DisplayInfo {
    private typealias Create = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
    private static let create: Create? = {
        let path = "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
              let symbol = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        return unsafeBitCast(symbol, to: Create.self)
    }()

    public let id: CGDirectDisplayID
    public let name: String
    public let location: String?
    public var builtIn: Bool { CGDisplayIsBuiltin(id) != 0 }

    public init(id: CGDirectDisplayID) {
        self.id = id
        let dictionary = Self.create?(id)?.takeRetainedValue() as? [String: Any]
        let names = dictionary?["DisplayProductName"] as? [String: String]
        name = names?["en_US"] ?? names?.values.sorted().first
            ?? (CGDisplayIsBuiltin(id) != 0 ? "MacBook 내장 화면" : "외장 화면")
        location = dictionary?["IODisplayLocation"] as? String
    }

    public static func activeIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    public static func id(at point: CGPoint) -> CGDirectDisplayID? {
        let displays = activeIDs().filter { CGDisplayBounds($0).contains(point) }
        if displays.count == 1 { return displays.first }
        // Overlapping or mirrored displays have no unique cursor target.
        return nil
    }
}
