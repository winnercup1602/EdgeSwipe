import AppKit
import CoreGraphics
import IOKit.hidsystem

public enum NativeBrightnessKeys {
    // Called by the serial control queue. AppKit events are built on main.
    public static func post(increase: Bool, on display: CGDirectDisplayID,
                            whileValid: () -> Bool) -> Bool {
        DispatchQueue.main.sync {
            guard whileValid(), BuiltInDisplay.activeID == display, CGPreflightPostEventAccess(),
                  let point = CGEvent(source: nil)?.location,
                  CGDisplayBounds(display).contains(point) else { return false }

            let key = increase ? NX_KEYTYPE_BRIGHTNESS_UP : NX_KEYTYPE_BRIGHTNESS_DOWN
            func event(_ state: Int32) -> CGEvent? {
                let flags = state << 8
                return NSEvent.otherEvent(
                    with: .systemDefined, location: .zero, modifierFlags: .init(rawValue: UInt(flags)),
                    timestamp: 0, windowNumber: 0, context: nil, subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                    data1: Int((key << 16) | flags), data2: -1
                )?.cgEvent
            }
            guard let down = event(NX_KEYDOWN), let up = event(NX_KEYUP) else { return false }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            return true
        }
    }
}
