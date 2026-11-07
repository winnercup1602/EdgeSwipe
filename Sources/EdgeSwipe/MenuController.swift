import AppKit
import GestureCore
import UniformTypeIdentifiers

struct MenuContext {
    let status: String
    let currentApp: NSRunningApplication?
    let permissionGranted: Bool
    let inputMonitoringNeeded: Bool
    let statusLines: [String]
    var loginEnabled = false
    var loginNeedsApproval = false
    var loginError: String?
    var canCheckUpdates = false
    var automaticUpdates = false
}

final class MenuController: NSObject {
    private let preferences: Preferences
    private let keyboardAvailable: Bool
    var onSettings: (GestureSettings) -> Void = { _ in }
    var onPause: () -> Void = {}
    var onExclusions: () -> Void = {}
    var onAccessibility: () -> Void = {}
    var onInputMonitoring: () -> Void = {}
    var onLogin: () -> Void = {}
    var onNews: () -> Void = {}
    var onReset: () -> Void = {}
    var onCheckUpdates: () -> Void = {}
    var onAutomaticUpdates: () -> Void = {}

    init(preferences: Preferences, keyboardAvailable: Bool) {
        self.preferences = preferences; self.keyboardAvailable = keyboardAvailable
    }

    func build(_ context: MenuContext) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        menu.addItem(disabled(context.status))
        menu.addItem(action(preferences.paused ? "다시 시작" : "일시정지", #selector(pause)))
        menu.addItem(.separator())
        let settings = preferences.settings
        let edges = submenu("가장자리 기능", in: menu)
        edges.addItem(setting("왼쪽 볼륨 · 오른쪽 밝기", selected: !settings.swapped) { $0.swapped = false })
        edges.addItem(setting("왼쪽 밝기 · 오른쪽 볼륨", selected: settings.swapped) { $0.swapped = true })
        edges.addItem(.separator())
        for edge in [Edge.top, .bottom] {
            let choices = submenu("\(edge == .top ? "위" : "아래"): \(settings.action(for: edge).title)", in: edges)
            for value in [GestureAction.switchApps, .scrubVideo, .keyboardBrightness, .media, .off] {
                let item = setting(value.title, selected: settings.action(for: edge) == value) {
                    if edge == .top { $0.top = value } else { $0.bottom = value }
                }
                if value == .keyboardBrightness && !keyboardAvailable { item.isEnabled = false }
                choices.addItem(item)
            }
        }
        let gestures = submenu("제스처 설정", in: menu)
        gestures.addItem(setting("정밀 조절 (¼ 단계)", selected: settings.precise) { $0.precise.toggle() })
        gestures.addItem(setting("조절 중 커서 고정", selected: settings.freezeCursor) { $0.freezeCursor.toggle() })
        gestures.addItem(setting("좌우 가장자리의 하단 25%만", selected: settings.bottomQuarterOnly) { $0.bottomQuarterOnly.toggle() })
        let middle = setting("세 손가락 탭으로 중간 클릭", selected: settings.threeFingerClick) { $0.threeFingerClick.toggle() }
        middle.toolTip = "macOS의 세 손가락 드래그·찾아보기와 동작이 겹칠 수 있습니다."
        gestures.addItem(middle)
        let widths = submenu("가장자리 너비", in: gestures)
        for value in EdgeWidth.allCases { widths.addItem(setting(value.title, selected: settings.width == value) { $0.width = value }) }
        let haptics = submenu("햅틱 강도", in: gestures)
        for value in HapticStrength.allCases { haptics.addItem(setting(value.title, selected: settings.haptics == value) { $0.haptics = value }) }
        let hold = submenu("제스처 허용 키", in: gestures)
        for value in HoldKey.allCases { hold.addItem(setting(value.title, selected: settings.holdKey == value) { $0.holdKey = value }) }
        let modes = submenu("키 사용 방식", in: gestures)
        for value in HoldMode.allCases { modes.addItem(setting(value.title, selected: settings.holdMode == value) { $0.holdMode = value }) }
        let corners = submenu("모서리 더블 탭", in: menu)
        for corner in Corner.allCases {
            let choices = submenu(corner.title, in: corners)
            for value in CornerAction.allCases {
                choices.addItem(setting(value.title, selected: (settings.corners[corner] ?? .off) == value) { $0.corners[corner] = value })
            }
        }
        let apps = submenu("앱별 일시정지", in: menu)
        if let app = context.currentApp, let id = app.bundleIdentifier {
            let item = action("\(app.localizedName ?? "현재 앱")에서 일시정지", #selector(toggleExcluded(_:)))
            item.representedObject = id
            item.state = preferences.excludedApps.contains(id) ? .on : .off
            apps.addItem(item)
        }
        apps.addItem(action("앱 추가…", #selector(chooseExcludedApp)))
        if !preferences.excludedApps.isEmpty { apps.addItem(.separator()) }
        for id in preferences.excludedApps.sorted() {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? id
            let item = action("\(name) 제외 해제", #selector(toggleExcluded(_:)))
            item.representedObject = id
            apps.addItem(item)
        }
        menu.addItem(.separator())
        let permission = context.permissionGranted ? "권한 안내…" : "권한 설정…"
        menu.addItem(action(permission, #selector(accessibility)))
        if context.inputMonitoringNeeded { menu.addItem(action("입력 모니터링 설정…", #selector(inputMonitoring))) }
        let status = submenu("장치 및 상태", in: menu)
        context.statusLines.forEach { status.addItem(disabled($0)) }
        let start = action("로그인 시 자동 실행", #selector(toggleLogin))
        start.state = context.loginEnabled ? .on : .off
        start.isEnabled = Bundle.main.bundleURL.pathExtension == "app"
        menu.addItem(start)
        if context.loginNeedsApproval { status.addItem(disabled("시스템 설정에서 로그인 항목 승인 필요")) }
        if let error = context.loginError { status.addItem(disabled(error)) }
        let updater = submenu("업데이트", in: menu)
        let check = action("업데이트 확인…", #selector(checkUpdates))
        check.isEnabled = context.canCheckUpdates
        updater.addItem(check)
        let automatic = action("업데이트 자동 확인", #selector(toggleAutomaticUpdates))
        automatic.state = context.automaticUpdates ? .on : .off
        updater.addItem(automatic)
        menu.addItem(action("새로운 기능…", #selector(news)))
        menu.addItem(action("기본 설정으로 초기화…", #selector(reset)))
        menu.addItem(.separator())
        menu.addItem(action("EdgeSwipe 종료", #selector(quit)))
        return menu
    }

    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        parent.addItem(item)
        return menu
    }
    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }
    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.isEnabled = false; return item
    }
    private func setting(_ title: String, selected: Bool, change: @escaping (inout GestureSettings) -> Void) -> NSMenuItem {
        let item = action(title, #selector(selectSetting(_:)))
        item.state = selected ? .on : .off
        item.representedObject = change
        return item
    }
    @objc private func selectSetting(_ item: NSMenuItem) {
        guard let change = item.representedObject as? (inout GestureSettings) -> Void else { return }
        var settings = preferences.settings
        change(&settings)
        onSettings(settings)
    }
    @objc private func toggleExcluded(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        if preferences.excludedApps.contains(id) { preferences.excludedApps.remove(id) } else { preferences.excludedApps.insert(id) }
        preferences.save()
        onExclusions()
    }
    @objc private func chooseExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "추가"
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                if let id = Bundle(url: url)?.bundleIdentifier, id != Bundle.main.bundleIdentifier {
                    self.preferences.excludedApps.insert(id)
                }
            }
            self.preferences.save()
            self.onExclusions()
        }
    }
    @objc private func pause() { onPause() }
    @objc private func accessibility() { onAccessibility() }
    @objc private func inputMonitoring() { onInputMonitoring() }
    @objc private func toggleLogin() { onLogin() }
    @objc private func checkUpdates() { onCheckUpdates() }
    @objc private func toggleAutomaticUpdates() { onAutomaticUpdates() }
    @objc private func news() { onNews() }
    @objc private func reset() { onReset() }
    @objc private func quit() { NSApp.terminate(nil) }
}
