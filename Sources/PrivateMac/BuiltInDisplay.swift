import CoreGraphics

public enum BuiltInDisplay {
    public static var activeID: CGDirectDisplayID? {
        let ids = DisplayInfo.activeIDs().filter {
            CGDisplayIsBuiltin($0) != 0 && CGDisplayIsAsleep($0) == 0
        }
        return ids.count == 1 ? ids.first : nil
    }
}
