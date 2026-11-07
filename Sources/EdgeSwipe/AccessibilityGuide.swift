import AppKit

final class AccessibilityGuide: NSWindowController {
    static var permissionName: String {
        if #available(macOS 27, *) { return "기기 제어 및 데이터 접근" }
        return "손쉬운 사용"
    }

    private let openSettings: () -> Bool
    private let locateSettings: () -> NSRect?
    private let settingsIsFrontmost: () -> Bool
    private let hint = NSTextField(wrappingLabelWithString: "")
    private var timer: Timer?
    private var foundSettings = false
    private var missingSince: TimeInterval?
    private var openingDeadline = 0.0
    private var dragging = false
    private(set) var isTracking = false

    init(openSettings: @escaping () -> Bool = {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        return NSWorkspace.shared.open(url)
    }, locateSettings: @escaping () -> NSRect? = SettingsWindowAnchor.frame,
         settingsIsFrontmost: @escaping () -> Bool = {
             NSWorkspace.shared.frontmostApplication?.bundleIdentifier == SettingsWindowAnchor.bundleIdentifier
         }) {
        self.openSettings = openSettings
        self.locateSettings = locateSettings
        self.settingsIsFrontmost = settingsIsFrontmost
        let panel = PermissionCardPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 136),
                                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "EdgeSwipe · 권한 설정"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        super.init(window: panel)

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        panel.contentView = background

        let title = NSTextField(labelWithString: "위의 앱 목록으로 드래그하세요")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "권한 안내 닫기")!,
                             target: self, action: #selector(dismiss))
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.setAccessibilityIdentifier("closePermissionGuide")
        let header = NSStackView(views: [title, NSView(), close])
        header.orientation = .horizontal

        let card = DraggableAppCard(appURL: Bundle.main.bundleURL)
        card.onDrag = { [weak self] dragging in
            guard let self else { return }
            self.dragging = dragging
            self.window?.ignoresMouseEvents = dragging
            self.window?.alphaValue = dragging ? 0.7 : 1
            if !dragging { self.followSettings() }
        }
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.stringValue = "이미 목록에 있으면 스위치를 켜세요. 승인되면 자동으로 닫힙니다."
        hint.setAccessibilityIdentifier("permissionStatus")
        let stack = NSStackView(views: [header, card, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            card.widthAnchor.constraint(equalTo: stack.widthAnchor),
            card.heightAnchor.constraint(equalToConstant: 48),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            close.widthAnchor.constraint(equalToConstant: 18),
            close.heightAnchor.constraint(equalToConstant: 18)
        ])
        panel.setContentSize(NSSize(width: 360, height: stack.fittingSize.height + 24))
    }

    required init?(coder: NSCoder) { return nil }

    func present(granted: Bool) {
        close()
        let opened = openSettings()
        guard !granted else { return }
        isTracking = true
        foundSettings = false
        missingSince = nil
        openingDeadline = ProcessInfo.processInfo.systemUptime + 8
        hint.stringValue = opened ? "이미 목록에 있으면 스위치를 켜세요. 승인되면 자동으로 닫힙니다."
            : "시스템 설정 → 개인정보 보호 및 보안 → \(Self.permissionName)을 여세요."
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.followSettings() }
        timer.tolerance = 0.03
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        followSettings()
    }

    func refresh(granted: Bool) {
        if granted, isTracking { close() }
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        isTracking = false
        dragging = false
        window?.ignoresMouseEvents = false
        window?.alphaValue = 1
        super.close()
    }

    private func followSettings() {
        guard isTracking, !dragging, let window else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let settings = locateSettings() {
            foundSettings = true
            missingSince = nil
            let frame = PermissionCardLayout.frame(below: settings, cardSize: window.frame.size,
                                                   screens: NSScreen.screens.map(\.visibleFrame))
            if window.frame != frame { window.setFrame(frame, display: true) }
            if settingsIsFrontmost() { window.orderFrontRegardless() }
            else { window.orderOut(nil) }
        } else if foundSettings {
            // Opening another Settings pane can briefly replace its window.
            window.orderOut(nil)
            if missingSince == nil { missingSince = now }
            if now - (missingSince ?? now) > 1 { close() }
        } else if now >= openingDeadline {
            // Do not leave a detached helper floating over unrelated apps.
            close()
        }
    }

    @objc private func dismiss() { close() }
}

private final class PermissionCardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DraggableAppCard: NSView, NSDraggingSource {
    private let appURL: URL
    private var mouseDownEvent: NSEvent?
    var onDrag: (Bool) -> Void = { _ in }

    init(appURL: URL) {
        self.appURL = appURL
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        layer?.cornerRadius = 8
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: appURL.path))
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: "EdgeSwipe")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let arrow = NSImageView(image: NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)!)
        arrow.contentTintColor = .secondaryLabelColor
        let row = NSStackView(views: [icon, title, NSView(), arrow])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36), icon.heightAnchor.constraint(equalToConstant: 36)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("EdgeSwipe 앱 카드, 위의 권한 목록으로 드래그")
        setAccessibilityIdentifier("draggableAppCard")
        toolTip = "EdgeSwipe.app을 위의 권한 목록으로 드래그"
    }

    required init?(coder: NSCoder) { return nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func mouseDown(with event: NSEvent) { mouseDownEvent = event }
    override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, appURL.pathExtension == "app" else { return }
        let delta = NSPoint(x: event.locationInWindow.x - start.locationInWindow.x,
                            y: event.locationInWindow.y - start.locationInWindow.y)
        guard hypot(delta.x, delta.y) >= 4 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48),
                              contents: NSWorkspace.shared.icon(forFile: appURL.path))
        beginDraggingSession(with: [item], event: start, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { onDrag(true) }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { onDrag(false) }
}
