import ApplicationServices
import Foundation

final class PointerFreeze {
    static let holdTimeout: TimeInterval = 0.30

    private let corrections = CursorCorrections()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onInterrupt: () -> Void = {}
    var onClick: () -> Void = {}

    var ready: Bool {
        guard let tap else { return false }
        return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
    }

    func start() {
        guard !ready, AXIsProcessTrusted() else { return }
        stop()
        let events: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: pointerTap, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        release()
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    func lock(at point: CGPoint) {
        corrections.begin(at: point)
    }

    func renew() {
        corrections.renew()
    }

    func release() {
        corrections.end()
    }

    fileprivate func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            release()
            // Re-create on the regular permission check, outside of the callback.
            DispatchQueue.main.async { [weak self] in self?.onInterrupt() }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            release()
            onClick()
        case .mouseMoved:
            if corrections.intercept(event.location) { return nil }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}

private let pointerTap: CGEventTapCallBack = { _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    return Unmanaged<PointerFreeze>.fromOpaque(context).takeUnretainedValue().handle(type, event: event)
}

private final class CursorCorrections {
    private struct Hold {
        let point: CGPoint
        let generation: UInt64
        var deadline: TimeInterval
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "io.github.winnercup1602.edgeswipe.cursor", qos: .userInteractive)
    private var hold: Hold?
    private var generation: UInt64 = 0
    private var correctionPending = false

    func begin(at point: CGPoint) {
        lock.lock()
        generation &+= 1
        hold = Hold(point: point, generation: generation,
                    deadline: ProcessInfo.processInfo.systemUptime + PointerFreeze.holdTimeout)
        lock.unlock()
    }

    func renew() {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        if let current = hold, now < current.deadline { hold?.deadline = now + PointerFreeze.holdTimeout }
        lock.unlock()
    }

    func end() {
        lock.lock()
        hold = nil
        lock.unlock()
    }

    func intercept(_ location: CGPoint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let current = hold, ProcessInfo.processInfo.systemUptime < current.deadline else {
            return false
        }
        if !correctionPending, location != current.point {
            correctionPending = true
            queue.async { [weak self] in self?.correct(current) }
        }
        return true
    }

    private func correct(_ requested: Hold) {
        lock.lock()
        let valid = hold.map {
            $0.generation == requested.generation && ProcessInfo.processInfo.systemUptime < $0.deadline
        } ?? false
        lock.unlock()

        // Quartz may move the physical cursor before it dispatches a mouse
        // event to a tap. Warp only while held and keep IPC off the tap callback.
        if valid { _ = CGWarpMouseCursorPosition(requested.point) }

        lock.lock()
        correctionPending = false
        lock.unlock()
    }
}
