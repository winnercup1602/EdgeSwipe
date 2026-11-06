import AppKit
import ApplicationServices
import GestureCore
import PrivateMac
import os

private final class OperationLease {
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
        let control: Control
        let lease = OperationLease()
        var lastFrame: TimeInterval
        var lastWrite = -Double.infinity
        var target: ControlTarget?
        var busy = false
        var recognized = false
    }

    private enum Suspension: Hashable { case sleep, screenSleep, inactive }

    private let trackpads = Trackpads()
    private let brightness = NativeBrightness()
    private let pointer = PointerFreeze()
    private let controls = DispatchQueue(label: "io.github.winnercup1602.edgeswipe.controls", qos: .userInteractive)
    private let logger = Logger(subsystem: "io.github.winnercup1602.edgeswipe", category: "app")
    private var recognizers: [UInt64: EdgeGesture] = [:]
    private var session: Session?
    private var strokeTimer: Timer?
    private var permissionTimer: Timer?
    private var suspension: Set<Suspension> = []
    private var observers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var trusted = false
    private var captureEnabled = false
    private var inputMonitoringNeeded = false
    private var paused = UserDefaults.standard.bool(forKey: "paused")
    private var controlErrors: [Control: String] = [:]
    private var builtInDisplay: CGDirectDisplayID?
    private var latestBrightnessStroke: OperationLease?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.statusIcon
        item.button?.setAccessibilityLabel("EdgeSwipe")
        item.button?.toolTip = "EdgeSwipe"
        statusItem = item
        trackpads.onFrame = { [weak self] device, contact in self?.receive(device, contact) }
        trackpads.onChanged = { [weak self] in self?.trackpadsChanged() }
        pointer.onClick = { [weak self] in self?.endStroke() }
        pointer.onInterrupt = { [weak self] in
            self?.endStroke()
            self?.checkPermission()
        }
        observePower()
        reconcile()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkPermission() }
        timer.tolerance = 0.2
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        cancelPendingBrightnessStep()
        endStroke()
        pointer.stop()
        trackpads.stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private func receive(_ device: UInt64, _ contact: TrackpadContact) {
        guard captureEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let active = session, now - active.lastFrame >= PointerFreeze.holdTimeout { endStroke() }
        var gesture = recognizers[device] ?? EdgeGesture()
        let touch: Touch
        switch contact {
        case .empty:
            touch = .none
        case let .finger(id, x, y):
            if let session, session.device != device {
                endStroke()
                gesture.cancel()
            }
            touch = .single(id: id, x: x, y: y)
        case .invalid:
            touch = .invalid
        }

        let transition = gesture.update(touch)
        recognizers[device] = gesture
        switch transition {
        case .started(let control):
            guard !mouseButtonIsDown else { recognizers[device]?.cancel(); return }
            var started = Session(device: device, control: control, lastFrame: now)
            if control == .brightness {
                guard let display = builtInDisplay, let brightness else {
                    recognizers[device]?.cancel()
                    return
                }
                cancelPendingBrightnessStep()
                latestBrightnessStroke = started.lease
                started.target = .brightness(BuiltInBrightness(display: display, native: brightness))
            }
            session = started
            let timer = Timer(timeInterval: Self.stepInterval, repeats: true) { [weak self] _ in self?.pump() }
            strokeTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .recognized:
            guard let active = session, active.device == device, !mouseButtonIsDown,
                  let point = CGEvent(source: nil)?.location else { endStroke(); return }
            session?.lastFrame = now
            session?.recognized = true
            pointer.lock(at: point)
            if active.control == .brightness { pump() } else { resolveAudio() }
        case .ended:
            if session?.device == device {
                endStroke(blockContact: false, allowAcceptedBrightnessStep: touch == .none)
            }
        case .unchanged:
            if session?.device == device, case .single = touch {
                session?.lastFrame = now
                if session?.recognized == true {
                    pointer.renew()
                    pump()
                }
            }
        }
    }

    private var mouseButtonIsDown: Bool {
        [.left, .right, .center].contains { CGEventSource.buttonState(.combinedSessionState, button: $0) }
    }

    private func resolveAudio() {
        guard let active = session else { return }
        controls.async { [weak self] in
            guard active.lease.valid else { return }
            let result = Result { ControlTarget.volume(try AudioOutput.current()) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.session?.lease === active.lease else { return }
                switch result {
                case .success(let target):
                    self.session?.target = target
                    self.pump()
                case .failure(let error):
                    self.report(error, for: active.control)
                    self.endStroke()
                }
            }
        }
    }

    private func pump() {
        guard let active = session else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - active.lastFrame < PointerFreeze.holdTimeout, pointer.ready else { endStroke(); return }
        guard let target = active.target, !active.busy, now - active.lastWrite >= Self.stepInterval,
              let direction = recognizers[active.device]?.nextStep() else { return }
        session?.busy = true
        session?.lastWrite = now

        controls.async { [weak self] in
            guard active.lease.valid else { return }
            let result = Result {
                let change = try target.adjust(direction) { active.lease.valid }
                guard active.lease.valid else { throw ControlFailure.cancelled }
                return change
            }
            DispatchQueue.main.async { [weak self] in self?.finish(result, active: active, direction: direction) }
        }
    }

    private func finish(_ result: Result<LevelChange?, Error>, active: Session, direction: Direction) {
        let stillTracking = session?.lease === active.lease
        let completingBrightness = latestBrightnessStroke === active.lease && active.lease.valid
        guard stillTracking || completingBrightness else { return }
        if stillTracking { session?.busy = false }
        switch result {
        case .success(let change):
            if controlErrors.removeValue(forKey: active.control) != nil { updateMenu() }
            if let change {
                if stillTracking { trackpads.tick(on: active.device, gain: change.hapticGain) }
                logger.info("Applied step to \(active.control == .volume ? "volume" : "brightness", privacy: .public), level \(change.level, privacy: .public)")
            } else if stillTracking {
                recognizers[active.device]?.discardTravel(in: direction)
            }
        case .failure(let error):
            report(error, for: active.control)
            if stillTracking { endStroke() }
        }
    }

    private func report(_ error: Error, for control: Control) {
        controlErrors[control] = String(describing: error)
        logger.error("Adjustment failed: \(String(describing: error), privacy: .public)")
        updateMenu()
    }

    private func endStroke(blockContact: Bool = true, allowAcceptedBrightnessStep: Bool = false) {
        if let active = session {
            if !(allowAcceptedBrightnessStep && active.control == .brightness && active.busy) {
                active.lease.cancel()
            }
            if blockContact { recognizers[active.device]?.cancel() }
        }
        session = nil
        strokeTimer?.invalidate()
        strokeTimer = nil
        pointer.release()
    }

    private func cancelPendingBrightnessStep() {
        latestBrightnessStroke?.cancel()
        latestBrightnessStroke = nil
    }

    private func trackpadsChanged() {
        let ids = Set(trackpads.status.map(\.id))
        recognizers = recognizers.filter { ids.contains($0.key) }
        updateMenu()
    }

    private func observePower() {
        let center = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, Suspension, Bool)] = [
            (NSWorkspace.willSleepNotification, .sleep, true),
            (NSWorkspace.didWakeNotification, .sleep, false),
            (NSWorkspace.screensDidSleepNotification, .screenSleep, true),
            (NSWorkspace.screensDidWakeNotification, .screenSleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .inactive, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .inactive, false)
        ]
        observers = events.map { name, reason, entering in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if entering { self.suspension.insert(reason) } else { self.suspension.remove(reason) }
                self.reconcile()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.endStroke()
            self?.controlErrors.removeValue(forKey: .brightness)
            self?.refreshBrightnessTarget()
            self?.updateMenu()
        }
    }

    private func reconcile() {
        if paused || !suspension.isEmpty {
            endStroke()
            cancelPendingBrightnessStep()
            trackpads.stop()
            pointer.stop()
            builtInDisplay = nil
        } else {
            trackpads.start()
            refreshBrightnessTarget()
        }
        checkPermission()
        updateMenu()
    }

    private func refreshBrightnessTarget() {
        cancelPendingBrightnessStep()
        builtInDisplay = nil
        guard !paused, suspension.isEmpty, brightness != nil else { return }
        builtInDisplay = BuiltInDisplay.activeID
    }

    private func checkPermission() {
        let wasReady = captureEnabled
        let wasTrusted = trusted
        let previouslyNeededMonitoring = inputMonitoringNeeded
        trusted = AXIsProcessTrusted()
        if !trusted {
            endStroke()
            if wasTrusted { cancelPendingBrightnessStep() }
            pointer.stop()
            recognizers.removeAll()
        } else if !paused, suspension.isEmpty {
            pointer.start()
        }
        captureEnabled = trusted && !paused && suspension.isEmpty && pointer.ready
        inputMonitoringNeeded = trusted && !captureEnabled && !paused && suspension.isEmpty
            && !CGPreflightListenEventAccess()
        if wasReady != captureEnabled || wasTrusted != trusted || inputMonitoringNeeded != previouslyNeededMonitoring {
            updateMenu()
        }
    }

    private func updateMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let status = paused ? "일시정지됨" : (suspension.isEmpty ? "EdgeSwipe" : "대기 중")
        menu.addItem(disabled(status))
        menu.addItem(action(paused ? "다시 시작" : "일시정지", #selector(togglePause)))
        menu.addItem(.separator())

        if !trusted || !CGPreflightPostEventAccess() {
            menu.addItem(action("손쉬운 사용 권한 설정…", #selector(requestAccessibility)))
        } else if inputMonitoringNeeded {
            menu.addItem(action("입력 모니터링 권한 설정…", #selector(requestInputMonitoring)))
        } else if !paused && suspension.isEmpty && !pointer.ready {
            menu.addItem(disabled("커서 고정에 필요한 입력 이벤트를 열 수 없음"))
        }

        if !trackpads.available {
            menu.addItem(disabled("트랙패드 API를 사용할 수 없음"))
        } else if !paused && suspension.isEmpty {
            let pads = trackpads.status
            if pads.isEmpty {
                menu.addItem(disabled(trackpads.detectedCount == 0 ? "연결된 Force Touch 트랙패드 없음" : "트랙패드 입력 연결 대기 중"))
            }
            for pad in pads {
                menu.addItem(disabled("\(pad.name) · \(pad.hapticsAvailable ? "햅틱 준비됨" : "햅틱 연결 대기 중")"))
            }
        }
        if !paused, suspension.isEmpty {
            menu.addItem(.separator())
            if brightness == nil {
                menu.addItem(disabled("내장 화면 밝기 API를 사용할 수 없음"))
            } else if builtInDisplay != nil {
                menu.addItem(disabled("MacBook 화면 밝기 준비됨"))
            } else {
                menu.addItem(disabled("밝기 조절은 MacBook 단독 화면 구성에서 사용 가능"))
            }
        }
        for control in [Control.volume, .brightness] {
            if let error = controlErrors[control] {
                menu.addItem(disabled("\(control == .volume ? "볼륨" : "밝기") · \(error)"))
            }
        }
        menu.addItem(.separator())
        menu.addItem(action("EdgeSwipe 종료", #selector(quit)))
        statusItem.menu = menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func togglePause() {
        paused.toggle()
        UserDefaults.standard.set(paused, forKey: "paused")
        reconcile()
    }

    @objc private func requestAccessibility() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
