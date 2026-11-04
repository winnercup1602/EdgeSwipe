import CoreFoundation
import Darwin
import Foundation
import IOKit
import MTLayout

public enum TrackpadContact: Equatable {
    case empty
    case finger(id: Int32, x: Double, y: Double)
    case invalid
}

public struct TrackpadStatus {
    public let id: UInt64
    public let name: String
    public let hapticsAvailable: Bool
}

private typealias MTCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32
) -> Int32

private final class MTAPI {
    typealias List = @convention(c) () -> Unmanaged<CFArray>?
    typealias Identify = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    typealias Flag = @convention(c) (UnsafeRawPointer) -> Bool
    typealias Register = @convention(c) (UnsafeRawPointer, MTCallback) -> Void
    typealias Start = @convention(c) (UnsafeRawPointer, Int32) -> Void
    typealias Stop = @convention(c) (UnsafeRawPointer) -> Void

    let list: List
    let identify: Identify
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop
    let running: Flag
    let haptics: Actuators?

    init?() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
              let list = dlsym(handle, "MTDeviceCreateList"),
              let identify = dlsym(handle, "MTDeviceGetDeviceID"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop"),
              let running = dlsym(handle, "MTDeviceIsRunning") else { return nil }
        self.list = unsafeBitCast(list, to: List.self)
        self.identify = unsafeBitCast(identify, to: Identify.self)
        self.register = unsafeBitCast(register, to: Register.self)
        self.unregister = unsafeBitCast(unregister, to: Register.self)
        self.start = unsafeBitCast(start, to: Start.self)
        self.stop = unsafeBitCast(stop, to: Stop.self)
        self.running = unsafeBitCast(running, to: Flag.self)
        self.haptics = Actuators(handle)
        // Keep the framework loaded for the process lifetime, including late callbacks.
    }

    struct Actuators {
        typealias Create = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
        typealias Open = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Int32
        typealias Actuate = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float, Float) -> Int32
        typealias Close = @convention(c) (UnsafeMutableRawPointer) -> Int32

        let create: Create
        let open: Open
        let actuate: Actuate
        let close: Close

        init?(_ handle: UnsafeMutableRawPointer) {
            guard let create = dlsym(handle, "MTActuatorCreateFromDeviceID"),
                  let open = dlsym(handle, "MTActuatorOpen"),
                  let actuate = dlsym(handle, "MTActuatorActuate"),
                  let close = dlsym(handle, "MTActuatorClose") else { return nil }
            self.create = unsafeBitCast(create, to: Create.self)
            self.open = unsafeBitCast(open, to: Open.self)
            self.actuate = unsafeBitCast(actuate, to: Actuate.self)
            self.close = unsafeBitCast(close, to: Close.self)
        }
    }
}

private final class FrameRelay {
    private let lock = NSLock()
    private var active = true
    private var queued = false
    private var frames: [TrackpadContact] = []
    private let receive: (TrackpadContact) -> Void

    init(receive: @escaping (TrackpadContact) -> Void) {
        self.receive = receive
    }

    func enqueue(_ frame: TrackpadContact) {
        lock.lock()
        guard active else { lock.unlock(); return }
        if frames.count >= 24 { frames = [.invalid] }
        frames.append(frame)
        if !queued {
            queued = true
            DispatchQueue.main.async { [weak self] in self?.drain() }
        }
        lock.unlock()
    }

    func invalidate() {
        lock.lock()
        active = false
        frames.removeAll()
        lock.unlock()
    }

    private func drain() {
        lock.lock()
        let pending = frames
        frames.removeAll(keepingCapacity: true)
        queued = false
        lock.unlock()
        pending.forEach(receive)
    }
}

private final class CallbackRoutes {
    static let shared = CallbackRoutes()
    private let lock = NSLock()
    private var relays: [UnsafeRawPointer: FrameRelay] = [:]

    func set(_ relay: FrameRelay?, for pointer: UnsafeRawPointer) {
        lock.lock()
        relays[pointer] = relay
        lock.unlock()
    }

    func relay(for pointer: UnsafeRawPointer) -> FrameRelay? {
        lock.lock()
        defer { lock.unlock() }
        return relays[pointer]
    }
}

private let contactCallback: MTCallback = { device, data, count, _, _ in
    guard let device, let relay = CallbackRoutes.shared.relay(for: UnsafeRawPointer(device)) else {
        return 0
    }
    guard (0...32).contains(count), count == 0 || data != nil else {
        relay.enqueue(.invalid)
        return 0
    }
    guard count > 0, let data else {
        relay.enqueue(.empty)
        return 0
    }

    let contacts = data.assumingMemoryBound(to: ESContact.self)
    var frame = TrackpadContact.empty
    for index in 0..<Int(count) {
        let contact = contacts[index]
        guard contact.state == 3 || contact.state == 4 else { continue }
        let x = Double(contact.x)
        let y = Double(contact.y)
        guard frame == .empty, (-0.08...1.08).contains(x), (-0.08...1.08).contains(y) else {
            frame = .invalid
            break
        }
        frame = .finger(id: contact.path, x: min(1, max(0, x)), y: min(1, max(0, y)))
    }
    relay.enqueue(frame)
    return 0
}

private struct HardwareTrackpad: Equatable {
    let registryID: UInt64
    let name: String

    static func connected() -> [UInt64: HardwareTrackpad] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"),
                                           &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        var result: [UInt64: HardwareTrackpad] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = unmanaged?.takeRetainedValue() as? [String: Any],
                  let id = (props["Multitouch ID"] as? NSNumber)?.uint64Value, id != 0,
                  (props["ForceSupported"] as? NSNumber)?.boolValue == true,
                  props["TrackpadSecondaryClickCorners"] != nil else { continue }

            let transport = props["Transport"] as? String ?? ""
            let product = props["Product"] as? String ?? ""
            let vendor = (props["VendorID"] as? NSNumber)?.intValue
            let name: String
            if product.contains("Internal") || transport == "FIFO" {
                name = "MacBook 내장 트랙패드"
            } else if (vendor == 0x4C || vendor == 0x05AC), ["Bluetooth", "USB"].contains(transport) {
                name = "Magic Trackpad (\(transport))"
            } else {
                continue
            }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { continue }
            result[id] = HardwareTrackpad(registryID: registryID, name: name)
        }
        return result
    }
}

public final class Trackpads {
    private struct Device {
        let hardware: HardwareTrackpad
        let ref: UnsafeRawPointer
        let relay: FrameRelay
        let generation: UInt64
        var actuator: UnsafeMutableRawPointer?
    }

    private let api = MTAPI()
    private var devices: [UInt64: Device] = [:]
    private var nextGeneration: UInt64 = 0
    private var timer: Timer?
    private var ticks = 0

    public var onFrame: (UInt64, TrackpadContact) -> Void = { _, _ in }
    public var onChanged: () -> Void = {}
    public var available: Bool { api != nil }
    public private(set) var detectedCount = 0

    public var status: [TrackpadStatus] {
        devices.map { id, device in
            TrackpadStatus(id: id, name: device.hardware.name, hapticsAvailable: device.actuator != nil)
        }.sorted { $0.name < $1.name }
    }

    public init() {}

    public func start() {
        guard timer == nil, api != nil else { return }
        refresh()
        // A lightweight registry reconciliation also catches Bluetooth devices
        // whose driver appears after the wake notification.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.2
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        for id in Array(devices.keys) { disconnect(id) }
        detectedCount = 0
        onChanged()
    }

    @discardableResult
    public func tick(on id: UInt64, gain: Float) -> Bool {
        guard let api = api?.haptics, let actuator = devices[id]?.actuator else { return false }
        // Empirical Force Touch waveform 5, with amplitude and duration multipliers.
        guard api.actuate(actuator, 5, 0, gain, 1) == 0 else {
            closeActuator(actuator)
            devices[id]?.actuator = nil
            onChanged()
            return false
        }
        return true
    }

    private func refresh() {
        guard let api else { return }
        let hardware = HardwareTrackpad.connected()
        let oldCount = detectedCount
        detectedCount = hardware.count
        var changed = oldCount != detectedCount
        ticks += 1
        for (id, device) in Array(devices) {
            if hardware[id] != device.hardware || !api.running(device.ref) {
                disconnect(id)
                changed = true
            } else if device.actuator == nil, ticks.isMultiple(of: 5),
                      let actuator = openActuator(id) {
                devices[id]?.actuator = actuator
                changed = true
            }
        }

        if hardware.keys.contains(where: { devices[$0] == nil }),
           let list = api.list()?.takeRetainedValue() {
            for index in 0..<CFArrayGetCount(list) {
                guard let ref = CFArrayGetValueAtIndex(list, index) else { continue }
                var id: UInt64 = 0
                guard api.identify(ref, &id) == 0, devices[id] == nil,
                      let candidate = hardware[id] else { continue }
                if connect(id, ref: ref, hardware: candidate, api: api) { changed = true }
            }
        }
        if changed { onChanged() }
    }

    private func connect(_ id: UInt64, ref: UnsafeRawPointer, hardware: HardwareTrackpad, api: MTAPI) -> Bool {
        nextGeneration &+= 1
        let generation = nextGeneration
        let relay = FrameRelay { [weak self] frame in
            guard let self, self.devices[id]?.generation == generation else { return }
            self.onFrame(id, frame)
        }
        _ = CFRetainDevice(ref)
        CallbackRoutes.shared.set(relay, for: ref)
        api.register(ref, contactCallback)
        api.start(ref, 0)
        guard api.running(ref) else {
            CallbackRoutes.shared.set(nil, for: ref)
            api.unregister(ref, contactCallback)
            releaseDevice(ref)
            return false
        }
        devices[id] = Device(hardware: hardware, ref: ref, relay: relay, generation: generation,
                             actuator: openActuator(id))
        return true
    }

    private func disconnect(_ id: UInt64) {
        guard let api, let device = devices.removeValue(forKey: id) else { return }
        onFrame(id, .invalid)
        device.relay.invalidate()
        CallbackRoutes.shared.set(nil, for: device.ref)
        api.unregister(device.ref, contactCallback)
        api.stop(device.ref)
        if let actuator = device.actuator { closeActuator(actuator) }
        releaseDevice(device.ref)
    }

    private func openActuator(_ id: UInt64) -> UnsafeMutableRawPointer? {
        guard let haptics = api?.haptics, let ref = haptics.create(id) else { return nil }
        guard haptics.open(ref, 0) == 0 else { releaseDevice(ref); return nil }
        return ref
    }

    private func closeActuator(_ ref: UnsafeMutableRawPointer) {
        _ = api?.haptics?.close(ref)
        releaseDevice(ref)
    }

    private func CFRetainDevice(_ ref: UnsafeRawPointer) -> Unmanaged<AnyObject> {
        Unmanaged<AnyObject>.fromOpaque(ref).retain()
    }

    private func releaseDevice(_ ref: UnsafeRawPointer) {
        Unmanaged<AnyObject>.fromOpaque(ref).release()
    }
}
