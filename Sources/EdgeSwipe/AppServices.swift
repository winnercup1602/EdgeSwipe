import AppKit
import ServiceManagement
import Sparkle

final class LoginService {
    private let service = SMAppService.mainApp
    private(set) var error: String?
    var enabled: Bool { service.status == .enabled || service.status == .requiresApproval }
    var needsApproval: Bool { service.status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try service.register() } else { try service.unregister() }
            error = nil
            if needsApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = "로그인 실행 설정 실패: \(error.localizedDescription)" }
    }
}

final class UpdateService {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private var observation: NSKeyValueObservation?
    var onChanged: () -> Void = {}
    var canCheck: Bool { controller.updater.canCheckForUpdates }
    var automatic: Bool { controller.updater.automaticallyChecksForUpdates }

    init() {
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.onChanged() }
        }
    }

    func start() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        controller.startUpdater()
    }

    func check() { controller.checkForUpdates(nil) }
    func setAutomatic(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled; onChanged() }
}

final class WhatsNewWindow: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 330),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "EdgeSwipe · 새로운 기능"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let title = NSTextField(labelWithString: "네 방향으로 더 많은 제어")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString:
            "• 위·아래 가장자리로 앱 전환, 동영상 탐색, 미디어와 키보드 밝기 조절\n\n" +
            "• 모서리 더블 탭과 세 손가락 중간 클릭\n\n" +
            "• 정밀 단계, 햅틱 강도, 가장자리 너비, 앱별 일시정지\n\n" +
            "• 커서가 있는 화면의 밝기와 로그인 실행·자동 업데이트")
        text.font = .systemFont(ofSize: 13)
        let button = NSButton(title: "계속", target: self, action: #selector(dismiss))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        let stack = NSStackView(views: [title, text, button])
        stack.orientation = .vertical
        stack.spacing = 24
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28),
            text.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.setContentSize(NSSize(width: 430, height: stack.fittingSize.height + 56))
        window.center()
    }

    required init?(coder: NSCoder) { return nil }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func dismiss() { close() }
}
