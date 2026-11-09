import AppKit
import CoreGraphics
import IOKit.hidsystem

public enum SystemInput {
    public static let eventTag: Int64 = 0x455357495045
    public enum MediaKey: Int32 {
        case volumeUp = 0, volumeDown = 1
        case brightnessUp = 2, brightnessDown = 3
        case playPause = 16, next = 17, previous = 18
    }

    public static func onMain<T>(_ work: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try work() }
        return try DispatchQueue.main.sync(execute: work)
    }

    @discardableResult
    public static func media(_ key: MediaKey, precise: Bool = false, whileValid: () -> Bool = { true }) -> Bool {
        onMain {
            guard whileValid(), CGPreflightPostEventAccess() else { return false }
            let modifiers: NSEvent.ModifierFlags = precise ? [.shift, .option] : []
            func event(_ state: Int32) -> CGEvent? {
                let flags = state << 8
                return NSEvent.otherEvent(with: .systemDefined, location: .zero,
                    modifierFlags: modifiers.union(.init(rawValue: UInt(flags))), timestamp: 0,
                    windowNumber: 0, context: nil, subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                    data1: Int((key.rawValue << 16) | flags), data2: -1)?.cgEvent
            }
            guard let down = event(NX_KEYDOWN), let up = event(NX_KEYUP) else { return false }
            for event in [down, up] {
                event.setIntegerValueField(.eventSourceUserData, value: eventTag)
                event.post(tap: .cghidEventTap)
            }
            return true
        }
    }

    @discardableResult
    public static func key(_ code: CGKeyCode, flags: CGEventFlags = [], whileValid: () -> Bool = { true }) -> Bool {
        onMain {
            guard whileValid(), CGPreflightPostEventAccess(),
                  let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return false }
            for event in [down, up] {
                event.flags = flags
                event.setIntegerValueField(.eventSourceUserData, value: eventTag)
                event.post(tap: .cghidEventTap)
            }
            return true
        }
    }

    @discardableResult
    public static func middleClick() -> Bool {
        guard CGPreflightPostEventAccess(), let point = CGEvent(source: nil)?.location,
              let down = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: point, mouseButton: .center),
              let up = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: point, mouseButton: .center) else { return false }
        for event in [down, up] {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(.eventSourceUserData, value: eventTag)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
