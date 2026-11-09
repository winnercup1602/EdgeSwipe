import AppKit
import CoreGraphics
import GestureCore
import IOKit.hidsystem

public enum NativeBrightnessKeys {
    public static func post(increase: Bool, on display: CGDirectDisplayID, precise: Bool = false,
                            whileValid: () -> Bool) -> Bool {
        SystemInput.onMain {
            guard whileValid(), BuiltInDisplay.activeID == display,
                  let point = CGEvent(source: nil)?.location,
                  CGDisplayBounds(display).contains(point) else { return false }
            return SystemInput.media(increase ? .brightnessUp : .brightnessDown, precise: precise,
                                     whileValid: whileValid)
        }
    }
}

public struct DisplayBrightnessKey {
    public static let eventType = CGEventType(rawValue: 14)!

    public enum Phase { case down, repeating, up }

    public let direction: Direction
    public let phase: Phase
    public let step: Double?

    public init?(event: CGEvent) {
        guard event.type == Self.eventType, let media = NSEvent(cgEvent: event),
              Int(media.subtype.rawValue) == Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS) else { return nil }
        let data = UInt32(truncatingIfNeeded: media.data1)
        switch Int32(data >> 16) {
        case NX_KEYTYPE_BRIGHTNESS_UP: direction = .up
        case NX_KEYTYPE_BRIGHTNESS_DOWN: direction = .down
        default: return nil
        }
        switch Int32((data >> 8) & 0xff) {
        case NX_KEYDOWN: phase = data & 1 == 0 ? .down : .repeating
        case NX_KEYUP: phase = .up
        default: return nil
        }

        let flags = event.flags
        let precise = flags.contains(.maskAlternate) && flags.contains(.maskShift)
        // Option alone opens Display settings. Command and Control have
        // system shortcuts of their own.
        if !flags.isDisjoint(with: [.maskCommand, .maskControl]) || (flags.contains(.maskAlternate) && !precise) {
            step = nil
        } else {
            step = precise ? Control.stepSize / 4 : Control.stepSize
        }
    }
}
