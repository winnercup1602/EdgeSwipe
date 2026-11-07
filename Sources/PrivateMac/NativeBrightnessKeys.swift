import CoreGraphics

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
