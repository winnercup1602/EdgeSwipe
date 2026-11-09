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
        let title = NSTextField(labelWithString: "화면 밝기 조절 개선")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString:
            "• 직결 모니터는 DDC/CI로 조절합니다. DDC/CI를 사용할 수 없으면 화면 밝기를 소프트웨어로 보정합니다.\n\n" +
            "• 밝기 키로 커서가 있는 직결 모니터를 조절할 수 있습니다. 내장 화면은 macOS 기본 밝기 제어를 사용합니다.\n\n" +
            "• 볼륨 스와이프에도 macOS 기본 음량 표시가 뜹니다.")
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
