import AppKit
import ApplicationServices
import GestureCore
import PrivateMac
import os

final class OperationLease: @unchecked Sendable {
    private let active = OSAllocatedUnfairLock(initialState: true)
    var valid: Bool { active.withLock { $0 } }
    func cancel() { active.withLock { $0 = false } }
}

final class EdgeSwipeApp: NSObject, NSApplicationDelegate {
    private static let stepInterval: TimeInterval = 0.04
    private static let statusIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let outline = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 16, height: 12),
                                       xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1.5
            outline.stroke()
            NSBezierPath(roundedRect: NSRect(x: 3.5, y: 5.5, width: 1.5, height: 7),
                         xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: NSRect(x: 13, y: 5.5, width: 1.5, height: 7),
                         xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    private struct Session {
        let device: UInt64
        let action: GestureAction
        let startPoint: CGPoint
        let settings: GestureSettings
        let lease = OperationLease()
        var lastFrame: TimeInterval
        var lastWrite = -Double.infinity
        var target: ControlTarget?
        var apps: AppSwitcher?
        var busy = false
        var recognized = false
    }
    private struct Input {
        var gesture: EdgeGesture
        var taps = TapGesture()
        var touching = false
        var suppressed = false
        init(settings: GestureSettings) { gesture = EdgeGesture(configuration: settings.configuration) }
    }
    private enum Suspension: Hashable { case sleep, screenSleep, inactive, excludedApp }
    private let trackpads = Trackpads()
    private let pointer = PointerFreeze()
    private let actions = NativeActions()
    private let keyboard: KeyboardBrightness?
    private let controls: DispatchQueue
    private let displays: DisplayControls
    private let feedback = SystemBrightnessFeedback()
    private let preferences: Preferences
    private let login = LoginService()
    private let updates = UpdateService()
    private let menuController: MenuController
    private let logger = Logger(subsystem: "io.github.winnercup1602.edgeswipe", category: "app")
    private var inputs: [UInt64: Input] = [:]
    private var session: Session?
    private var strokeTimer: Timer?
    private var permissionTimer: Timer?
    private var suspension: Set<Suspension> = []
    private var observers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var accessibilityGuide: AccessibilityGuide?
    private var newsWindow: WhatsNewWindow?
    private var pendingNews = false
    private var trusted = false
    private var postingAllowed = false
    private var captureEnabled = false
    private var inputMonitoringNeeded = false
    private var holdGate = HoldGate()
    private var lastTyping = -Double.infinity
    private var controlErrors: [GestureAction: String] = [:]
    private var latestBrightnessStroke: OperationLease?
    private var tapLease: OperationLease?
    private var currentUserApp: NSRunningApplication?

    override init() {
        let queue = DispatchQueue(label: "io.github.winnercup1602.edgeswipe.controls", qos: .userInteractive)
        controls = queue
        let keyboard = KeyboardBrightness()
        self.keyboard = keyboard
        let preferences = Preferences(hasKeyboardBacklight: keyboard != nil)
        self.preferences = preferences
        displays = DisplayControls(queue: queue)
        menuController = MenuController(preferences: preferences, keyboardAvailable: keyboard != nil)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.statusIcon
        item.button?.setAccessibilityLabel("EdgeSwipe")
        statusItem = item
        trackpads.onFrame = { [weak self] device, frame in self?.receive(device, frame) }
        trackpads.onChanged = { [weak self] in self?.trackpadsChanged() }
        pointer.onClick = { [weak self] in self?.cancelInput() }
        pointer.onFlagsChanged = { [weak self] flags in
            guard let self else { return }
            let settings = self.preferences.settings
            if self.holdGate.flagsChanged(flags, key: settings.holdKey, mode: settings.holdMode) {
                self.cancelInput()
                DispatchQueue.main.async { [weak self] in self?.updateMenu() }
            }
        }
        pointer.onTyping = { [weak self] in
            self?.lastTyping = ProcessInfo.processInfo.systemUptime
            self?.cancelInput()
        }
        pointer.onBrightnessKey = { [weak self] key in
            guard let self, self.captureEnabled else { return false }
            let handled = self.displays.handleKey(key)
            if handled, key.phase == .down, self.session?.action == .brightness { self.cancelInput() }
            return handled
        }
        pointer.onInterrupt = { [weak self] in self?.cancelInput(); self?.checkPermission() }
        displays.onChanged = { [weak self] in self?.updateMenu() }
        displays.onKeyAdjustment = { [weak self] error in
            guard let self else { return }
            if let error { self.report(error, for: .brightness) }
            else if self.controlErrors.removeValue(forKey: .brightness) != nil { self.updateMenu() }
        }
        displays.onAvailabilityChange = { [weak self] in
            guard let self, !self.preferences.paused, self.suspension.isEmpty else { return }
            self.cancelInput()
            self.displays.refresh()
        }
        feedback.onFailure = { [weak self] in
            self?.controlErrors[.brightness] = "macOS 밝기 표시 서비스에 연결할 수 없음"
            self?.updateMenu()
        }
        bindMenu()
        observeWorkspace()
        foregroundChanged()
        reconcile()
        updates.onChanged = { [weak self] in self?.updateMenu() }
        updates.start()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkPermission() }
        timer.tolerance = 0.2
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        let defaults = UserDefaults.standard
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let previous = defaults.string(forKey: "lastShownVersion")
        let upgrading = previous != nil || defaults.object(forKey: "paused") != nil || defaults.object(forKey: "edgesSwapped") != nil
        pendingNews = upgrading && previous != version
        if !upgrading { defaults.set(version, forKey: "lastShownVersion") }
        if !trusted || !postingAllowed { requestAccessibility() }
        else if pendingNews { showNews() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        cancelInput()
        pointer.stop()
        trackpads.stop()
        displays.stop(restoreSoftware: true)
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private var gateOpen: Bool {
        holdGate.permits(key: preferences.settings.holdKey, mode: preferences.settings.holdMode,
                         flags: CGEventSource.flagsState(.hidSystemState).rawValue)
            && ProcessInfo.processInfo.systemUptime - lastTyping >= 0.35
    }
    private var mouseButtonIsDown: Bool {
        [CGMouseButton.left, .right, .center].contains {
            if $0 == .left, pointer.suppressingTapClick { return false }
            return CGEventSource.buttonState(.combinedSessionState, button: $0)
        }
    }

    private func receive(_ device: UInt64, _ contact: TrackpadContact) {
        guard captureEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var input = inputs[device] ?? Input(settings: preferences.settings)
        let fingers: [Finger]
        switch contact {
        case .empty: fingers = []
        case .invalid:
            endStroke()
            input.gesture.cancel(); input.taps.cancel(); input.suppressed = true
            inputs[device] = input
            return
        case .contacts(let contacts):
            fingers = contacts.map { Finger(id: $0.id, x: $0.x, y: $0.y, size: $0.size, majorAxis: $0.majorAxis) }
        }
        input.touching = !fingers.isEmpty
        if !fingers.isEmpty { tapLease?.cancel() }
        if !gateOpen || mouseButtonIsDown || fingers.contains(where: { !$0.valid || $0.palm }) {
            cancelInput()
            input.suppressed = !fingers.isEmpty
            input.gesture.cancel(); input.taps.cancel()
        }
        if input.suppressed {
            if fingers.isEmpty { input = Input(settings: preferences.settings) }
            inputs[device] = input
            return
        }
        if let active = session, active.device != device, !fingers.isEmpty {
            endStroke()
            input.suppressed = true
            inputs[device] = input
            return
        }
        if let active = session, now - active.lastFrame >= PointerFreeze.holdTimeout { endStroke() }
        let touch: Touch
        if fingers.isEmpty { touch = .none }
        else if fingers.count == 1 { let f = fingers[0]; touch = .single(id: f.id, x: f.x, y: f.y) }
        else { touch = .invalid }
        let transition = input.gesture.update(touch, at: now)
        if transition == .recognized { input.taps.cancel() }
        let tap = input.taps.update(fingers, at: now, settings: preferences.settings)
        if input.taps.consumesClick { pointer.suppressTapClick() }
        inputs[device] = input
        switch transition {
        case .started(let edge):
            guard let point = CGEvent(source: nil)?.location else { return }
            cancelPendingBrightness()
            session = Session(device: device, action: preferences.settings.action(for: edge), startPoint: point,
                              settings: preferences.settings, lastFrame: now)
            strokeTimer?.invalidate()
            let timer = Timer(timeInterval: Self.stepInterval, repeats: true) { [weak self] _ in self?.pump() }
            strokeTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .recognized:
            guard let active = session, active.device == device, let point = CGEvent(source: nil)?.location else { endStroke(); return }
            session?.recognized = true
            session?.lastFrame = now
            if active.settings.freezeCursor { pointer.lock(at: point) }
            do {
                switch active.action {
                case .volume: resolveAudio()
                case .brightness:
                    session?.target = try displays.target(at: active.startPoint)
                    latestBrightnessStroke = active.lease
                case .keyboardBrightness:
                    guard let keyboard else { throw ControlFailure.keyboardUnavailable }
                    session?.target = .keyboard(keyboard)
                case .switchApps:
                    guard let apps = AppSwitcher() else { throw ControlFailure.inputUnavailable }
                    session?.apps = apps
                default: break
                }
                pump()
            } catch { report(error, for: active.action); endStroke() }
        case .ended:
            if session?.device == device {
                endStroke(blockContact: false, allowAcceptedBrightnessStep: fingers.isEmpty, commitAppSwitch: fingers.isEmpty)
            }
        case .unchanged:
            if session?.device == device, fingers.count == 1 {
                session?.lastFrame = now
                session?.apps?.renew()
                if session?.recognized == true { if session?.settings.freezeCursor == true { pointer.renew() }; pump() }
            }
        }
        if let tap { perform(tap, on: device) }
    }

    private func resolveAudio() {
        guard let active = session else { return }
        controls.async { [weak self] in
            guard active.lease.valid else { return }
            let result = Result { ControlTarget.volume(try AudioOutput.current()) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.session?.lease === active.lease else { return }
                switch result {
                case .success(let target): self.session?.target = target; self.pump()
                case .failure(let error): self.report(error, for: active.action); self.endStroke()
                }
            }
        }
    }

    private func pump() {
        guard let active = session else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard captureEnabled, gateOpen, !mouseButtonIsDown,
              now - active.lastFrame < PointerFreeze.holdTimeout, pointer.ready else { cancelInput(); return }
        guard active.recognized, !active.busy, now - active.lastWrite >= Self.stepInterval else { return }
        if [.volume, .brightness, .keyboardBrightness].contains(active.action), active.target == nil { return }
        guard let direction = inputs[active.device]?.gesture.nextStep(at: now) else { return }
        session?.busy = true
        session?.lastWrite = now
        if let target = active.target {
            controls.async { [weak self] in
                guard active.lease.valid else { return }
                let result = Result { () -> LevelChange? in
                    let change = try target.adjust(direction, step: active.settings.step) { active.lease.valid }
                    guard active.lease.valid else { throw ControlFailure.cancelled }
                    return change
                }
                DispatchQueue.main.async { [weak self] in self?.finish(result, active: active, direction: direction) }
            }
        } else {
            let result = Result { try NativeActions.step(active.action, direction, apps: active.apps) { active.lease.valid } }
            finish(result, active: active, direction: direction)
        }
    }

    private func finish(_ result: Result<LevelChange?, Error>, active: Session, direction: Direction) {
        let tracking = session?.lease === active.lease
        guard tracking || (latestBrightnessStroke === active.lease && active.lease.valid) else { return }
        if tracking { session?.busy = false }
        switch result {
        case .success(let change):
            var menuChanged = controlErrors.removeValue(forKey: active.action) != nil
            if case .external(let target) = active.target, displays.updatePath(for: target) {
                menuChanged = true
            }
            if menuChanged { updateMenu() }
            if let change {
                if let display = active.target?.feedbackDisplay { feedback.show(change.level, on: display) }
                if tracking { tick(device: active.device, level: change.level, strength: active.settings.haptics) }
            } else if tracking { inputs[active.device]?.gesture.discardTravel(in: direction) }
        case .failure(let error): report(error, for: active.action); if tracking { endStroke() }
        }
    }

    private func perform(_ tap: TapAction, on device: UInt64) {
        guard gateOpen, captureEnabled else { return }
        endStroke()
        tapLease?.cancel()
        let lease = OperationLease(); tapLease = lease
        let strength = preferences.settings.haptics
        controls.async { [weak self] in
            guard let self, lease.valid else { return }
            let result = Result { try self.actions.tap(tap) { lease.valid } }
            DispatchQueue.main.async { [weak self] in
                guard let self, lease.valid else { return }
                switch result {
                case .success(let change): if let change { self.tick(device: device, level: change.level, strength: strength) }
                case .failure(let error): self.report(error, for: .media)
                }
            }
        }
    }

    private func tick(device: UInt64, level: Double, strength: HapticStrength) {
        let gain = strength.gain(level: level)
        if gain > 0 { trackpads.tick(on: device, gain: gain) }
    }
    private func report(_ error: Error, for action: GestureAction) {
        if case ControlFailure.cancelled = error { return }
        controlErrors[action] = String(describing: error)
        logger.error("Adjustment failed: \(String(describing: error), privacy: .public)")
        updateMenu()
    }
    private func endStroke(blockContact: Bool = true, allowAcceptedBrightnessStep: Bool = false, commitAppSwitch: Bool = false) {
        if let active = session {
            active.apps?.finish(commit: commitAppSwitch)
            if !(allowAcceptedBrightnessStep && active.action == .brightness && active.busy) { active.lease.cancel() }
            if blockContact { inputs[active.device]?.gesture.cancel(); inputs[active.device]?.taps.cancel() }
        }
        session = nil
        strokeTimer?.invalidate(); strokeTimer = nil
        pointer.release()
    }
    private func cancelPendingBrightness() { latestBrightnessStroke?.cancel(); latestBrightnessStroke = nil }
    private func cancelInput() {
        endStroke()
        cancelPendingBrightness()
        tapLease?.cancel(); tapLease = nil
        for (id, input) in inputs {
            var replacement = Input(settings: preferences.settings)
            replacement.touching = input.touching
            replacement.suppressed = input.touching
            inputs[id] = replacement
        }
    }
    private func trackpadsChanged() {
        tapLease?.cancel()
        let ids = Set(trackpads.status.map(\.id))
        inputs = inputs.filter { ids.contains($0.key) }
        if let active = session, !ids.contains(active.device) { cancelInput() }
        updateMenu()
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, Suspension, Bool)] = [
            (NSWorkspace.willSleepNotification, .sleep, true), (NSWorkspace.didWakeNotification, .sleep, false),
            (NSWorkspace.screensDidSleepNotification, .screenSleep, true), (NSWorkspace.screensDidWakeNotification, .screenSleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .inactive, true), (NSWorkspace.sessionDidBecomeActiveNotification, .inactive, false)
        ]
        observers = events.map { name, reason, entering in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if entering { self.suspension.insert(reason) } else { self.suspension.remove(reason) }
                self.reconcile()
            }
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.foregroundChanged() })
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.cancelInput()
            if !self.preferences.paused, self.suspension.isEmpty { self.displays.refresh() }
        }
    }
    private func foregroundChanged() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            currentUserApp = front
        }
        let blocked = front?.bundleIdentifier.map { preferences.excludedApps.contains($0) } ?? false
        let changed = blocked != suspension.contains(.excludedApp)
        if blocked { suspension.insert(.excludedApp) } else { suspension.remove(.excludedApp) }
        if changed { reconcile() } else { updateMenu() }
    }
    private func reconcile() {
        cancelInput()
        if preferences.paused || !suspension.isEmpty {
            captureEnabled = false
            trackpads.stop(); pointer.stop(); displays.stop()
        } else { trackpads.start(); displays.refresh() }
        checkPermission()
        updateMenu()
    }
    private func checkPermission() {
        let previous = (trusted, postingAllowed, captureEnabled, inputMonitoringNeeded)
        trusted = AXIsProcessTrusted()
        postingAllowed = CGPreflightPostEventAccess()
        if !trusted || !postingAllowed { cancelInput(); pointer.stop() }
        else if !preferences.paused, suspension.isEmpty { pointer.start() }
        captureEnabled = trusted && postingAllowed && !preferences.paused && suspension.isEmpty && pointer.ready
        if previous.2 && !captureEnabled { displays.cancelKeys() }
        inputMonitoringNeeded = trusted && postingAllowed && !captureEnabled && !preferences.paused && suspension.isEmpty && !CGPreflightListenEventAccess()
        accessibilityGuide?.refresh(granted: trusted && postingAllowed)
        if previous != (trusted, postingAllowed, captureEnabled, inputMonitoringNeeded) { updateMenu() }
        if pendingNews, trusted, postingAllowed, accessibilityGuide?.window?.isVisible != true { showNews() }
    }
    private func bindMenu() {
        menuController.onSettings = { [weak self] settings in
            guard let self else { return }
            self.preferences.settings = settings; self.preferences.save(); self.holdGate.reset(flags: CGEventSource.flagsState(.hidSystemState).rawValue); self.cancelInput(); self.controlErrors.removeAll(); self.updateMenu()
        }
        menuController.onPause = { [weak self] in
            guard let self else { return }; self.preferences.paused.toggle(); self.preferences.save(); self.reconcile()
        }
        menuController.onExclusions = { [weak self] in self?.foregroundChanged() }
        menuController.onAccessibility = { [weak self] in self?.requestAccessibility() }
        menuController.onInputMonitoring = {
            _ = CGRequestListenEventAccess()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
        }
        menuController.onLogin = { [weak self] in guard let self else { return }; self.login.setEnabled(!self.login.enabled); self.updateMenu() }
        menuController.onCheckUpdates = { [weak self] in self?.updates.check() }
        menuController.onAutomaticUpdates = { [weak self] in guard let self else { return }; self.updates.setAutomatic(!self.updates.automatic) }
        menuController.onNews = { [weak self] in self?.showNews() }
        menuController.onReset = { [weak self] in self?.resetSettings() }
    }
    private func updateMenu() {
        guard let statusItem else { return }
        let status = preferences.paused ? "일시정지됨" : suspension.contains(.excludedApp) ? "현재 앱에서 일시정지됨" : suspension.isEmpty ? (preferences.settings.holdKey != .none && preferences.settings.holdMode == .toggle && !holdGate.latched ? "허용 키로 제스처 켜기" : "EdgeSwipe") : "대기 중"
        var lines = trackpads.status.map { "\($0.name) · \($0.hapticsAvailable ? "햅틱 준비됨" : "햅틱 연결 대기 중")" }
        if !trackpads.available { lines.append("트랙패드 API를 사용할 수 없음") }
        if displays.scanning { lines.append("화면 연결 확인 중") }
        lines += displays.screens.values.sorted { $0.info.id < $1.info.id }.map { "\($0.info.name) · \($0.status)" }
        if keyboard == nil { lines.append("키보드 백라이트 없음") }
        lines += controlErrors.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.title) · \($0.value)" }
        if lines.isEmpty { lines.append(status) }
        statusItem.button?.toolTip = "EdgeSwipe · " + status
        statusItem.menu = menuController.build(MenuContext(status: status, currentApp: currentUserApp,
            permissionGranted: trusted && postingAllowed, inputMonitoringNeeded: inputMonitoringNeeded, statusLines: lines, loginEnabled: login.enabled, loginNeedsApproval: login.needsApproval,
            loginError: login.error, canCheckUpdates: updates.canCheck, automaticUpdates: updates.automatic))
    }
    private func requestAccessibility() {
        if accessibilityGuide == nil { accessibilityGuide = AccessibilityGuide() }
        accessibilityGuide?.present(granted: trusted && postingAllowed)
    }
    private func showNews() {
        pendingNews = false
        UserDefaults.standard.set(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"), forKey: "lastShownVersion")
        if newsWindow == nil { newsWindow = WhatsNewWindow() }
        newsWindow?.present()
    }
    private func resetSettings() {
        let alert = NSAlert(); alert.messageText = "EdgeSwipe 설정을 초기화할까요?"
        alert.informativeText = "제스처 설정과 앱별 일시정지 목록을 초기화하고, 로그인 실행과 업데이트 자동 확인을 끕니다."
        alert.addButton(withTitle: "초기화"); alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        preferences.reset(); holdGate.reset(); controlErrors.removeAll()
        if login.enabled { login.setEnabled(false) }
        updates.setAutomatic(false)
        suspension.remove(.excludedApp); reconcile()
    }
}
