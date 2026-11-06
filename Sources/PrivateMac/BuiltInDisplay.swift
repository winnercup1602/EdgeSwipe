import CoreGraphics

public enum BuiltInDisplay {
    public static var activeID: CGDirectDisplayID? {
        // Two slots are enough to reject a second display, including mirrors.
        var displays = [CGDirectDisplayID](repeating: 0, count: 2)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(2, &displays, &count) == .success, count == 1 else { return nil }
        let display = displays[0]
        guard CGDisplayIsBuiltin(display) != 0, CGDisplayIsActive(display) != 0,
              CGDisplayIsAsleep(display) == 0 else { return nil }
        return display
    }
}
