import AppKit

enum SettingsWindowAnchor {
    static let bundleIdentifier = "com.apple.systempreferences"

    static func frame() -> NSRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let primary = NSScreen.screens.first else { return nil }
        // Window-server coordinates start at the top left of the primary
        // display; AppKit coordinates start at its bottom left.
        return windows.compactMap { info -> NSRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 320, rect.height > 240 else { return nil }
            return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }.max { $0.width * $0.height < $1.width * $1.height }
    }
}

enum PermissionCardLayout {
    static func frame(below settings: NSRect, cardSize: NSSize, screens: [NSRect]) -> NSRect {
        let screen = screens.max {
            area($0.intersection(settings)) < area($1.intersection(settings))
        } ?? settings
        let contentLeft = settings.minX + min(230, settings.width * 0.35)
        let x = (contentLeft + settings.maxX - cardSize.width) / 2
        // Clamp when the Settings window leaves no space below it. During a
        // drag, the card becomes mouse-transparent so it cannot block the list.
        return NSRect(x: min(max(screen.minX + 10, x), max(screen.minX + 10, screen.maxX - cardSize.width - 10)),
                      y: min(max(screen.minY + 10, settings.minY - cardSize.height - 8),
                             max(screen.minY + 10, screen.maxY - cardSize.height - 10)),
                      width: cardSize.width, height: cardSize.height)
    }

    private static func area(_ rect: NSRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}
