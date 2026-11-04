import AppKit
import CoreGraphics
import GestureCore
import IOKit.hidsystem
import PrivateMac

enum BrightnessKeys {
    private static let vorssaintID = "com.vorssaint.utils"

    // The event is the same brightness-key press that Vorssaint already
    // handles. EdgeSwipe does not also write the display after posting it.
    static func post(_ direction: Direction, on display: CGDirectDisplayID, builtIn: Bool,
                     whileValid: () -> Bool = { true }) -> Bool {
        DispatchQueue.main.sync {
            guard whileValid(), CGPreflightPostEventAccess(),
                  !NSRunningApplication.runningApplications(withBundleIdentifier: vorssaintID).isEmpty,
                  let point = CGEvent(source: nil)?.location,
                  DisplayInfo.id(at: point) == display else { return false }

            guard builtIn || UserDefaults(suiteName: vorssaintID)?.bool(forKey: "brightnessKeysEnabled") == true
            else { return false }

            let key = direction == .up ? NX_KEYTYPE_BRIGHTNESS_UP : NX_KEYTYPE_BRIGHTNESS_DOWN
            func event(_ state: Int32) -> CGEvent? {
                let flags = state << 8
                return NSEvent.otherEvent(
                    with: .systemDefined, location: .zero, modifierFlags: .init(rawValue: UInt(flags)),
                    timestamp: 0, windowNumber: 0, context: nil, subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                    data1: Int((key << 16) | flags), data2: -1
                )?.cgEvent
            }
            guard let down = event(NX_KEYDOWN), let up = event(NX_KEYUP) else { return false }
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
            return true
        }
    }
}
