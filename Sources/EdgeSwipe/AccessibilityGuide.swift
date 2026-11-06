import AppKit

final class AccessibilityGuide: NSWindowController {
    static var permissionName: String {
        if #available(macOS 27, *) { return "기기 제어 및 데이터 접근" }
        return "손쉬운 사용"
    }

    private let status = NSTextField(wrappingLabelWithString: "")
    private let settingsButton = NSButton(title: "설정 열기", target: nil, action: nil)
    private let closeButton = NSButton(title: "나중에", target: nil, action: nil)
    private var settingsOpenFailed = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "EdgeSwipe · 권한 안내"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        super.init(window: window)

        let appURL = Bundle.main.bundleURL
        let icon = DraggableAppIcon(appURL: appURL)
        let title = label("스와이프를 시작하기 전에", size: 22, weight: .semibold)
        let subtitle = label("스와이프 중 커서를 고정하려면\n‘\(Self.permissionName)’ 권한이 필요합니다.", color: .secondaryLabelColor)
        let dragHint = label("이 앱 아이콘을 설정 목록으로 드래그하세요", size: 12, color: .secondaryLabelColor)
        let steps = label("1. 아래 버튼으로 권한 설정을 여세요.\n2. 위 아이콘을 앱 목록으로 드래그하세요.\n3. EdgeSwipe 옆의 스위치를 켜세요.")
        steps.alignment = .left
        let note = label("이미 목록에 있으면 스위치만 켜세요.\n업데이트 후 인식되지 않으면 껐다 켜거나 다시 추가하세요.\n드래그가 안 되면 목록의 + 버튼으로 앱을 추가할 수 있습니다.",
                         size: 11, color: .secondaryLabelColor)
        if appURL.pathExtension != "app" {
            dragHint.stringValue = "설치된 EdgeSwipe.app에서 아이콘을 드래그할 수 있습니다"
        }

        status.font = .systemFont(ofSize: 12)
        status.alignment = .center
        status.setAccessibilityIdentifier("permissionStatus")
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        settingsButton.bezelStyle = .rounded
        settingsButton.setAccessibilityIdentifier("openAccessibilitySettings")
        closeButton.target = self
        closeButton.action = #selector(dismissGuide)
        closeButton.bezelStyle = .rounded
        closeButton.setAccessibilityIdentifier("closePermissionGuide")
        let buttons = NSStackView(views: [closeButton, settingsButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [title, subtitle, icon, dragHint, steps, note, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(6, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            icon.widthAnchor.constraint(equalToConstant: 88),
            icon.heightAnchor.constraint(equalToConstant: 88),
            steps.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.setContentSize(NSSize(width: 440, height: stack.fittingSize.height + 52))
        window.center()
    }

    required init?(coder: NSCoder) { return nil }

    func present(granted: Bool) {
        refresh(granted: granted)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh(granted: Bool) {
        status.stringValue = granted ? "✓ 권한이 허용되었습니다."
            : (settingsOpenFailed ? "설정을 열지 못했습니다. 시스템 설정에서 손쉬운 사용을 여세요." : "권한을 켜면 여기서 자동으로 확인합니다.")
        status.textColor = granted ? .systemGreen : (settingsOpenFailed ? .systemRed : .secondaryLabelColor)
        closeButton.title = granted ? "완료" : "나중에"
        closeButton.keyEquivalent = granted ? "\r" : ""
        settingsButton.keyEquivalent = granted ? "" : "\r"
    }

    @objc private func openSettings() {
        if let window, let screen = window.screen ?? NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.minX + 20, y: max(frame.minY, frame.midY - window.frame.height / 2)))
        }
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        settingsOpenFailed = !NSWorkspace.shared.open(url)
        if settingsOpenFailed { refresh(granted: false) }
    }

    @objc private func dismissGuide() { close() }

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = .center
        return label
    }
}

private final class DraggableAppIcon: NSImageView, NSDraggingSource {
    private let appURL: URL
    private var mouseDownEvent: NSEvent?

    init(appURL: URL) {
        self.appURL = appURL
        super.init(frame: .zero)
        image = NSWorkspace.shared.icon(forFile: appURL.path)
        imageScaling = .scaleProportionallyUpOrDown
        toolTip = "EdgeSwipe.app을 권한 설정의 앱 목록으로 드래그"
        setAccessibilityLabel("EdgeSwipe 앱 아이콘, 권한 설정의 앱 목록으로 드래그")
        setAccessibilityIdentifier("draggableAppIcon")
    }

    required init?(coder: NSCoder) { return nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { mouseDownEvent = event }

    override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, appURL.pathExtension == "app", let image else { return }
        let delta = NSPoint(x: event.locationInWindow.x - start.locationInWindow.x,
                            y: event.locationInWindow.y - start.locationInWindow.y)
        guard hypot(delta.x, delta.y) >= 4 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        let session = beginDraggingSession(with: [item], event: start, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
