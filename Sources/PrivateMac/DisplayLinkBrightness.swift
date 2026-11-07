import CoreGraphics
import Foundation

// DisplayLink Manager 16.2's local display-control notifications. Requests
// and waits run on the serial control queue. Foundation delivers replies on
// the main run loop, which stays free for input and UI.
public final class DisplayLinkBrightness {
    public struct Screen: Decodable {
        public let displayID: CGDirectDisplayID
        public let name: String
        fileprivate let persistentDisplayId: String
        fileprivate var brightness: Double
        fileprivate let isEnabled: Bool

        private enum CodingKeys: String, CodingKey {
            case displayID = "CGID"
            case name, persistentDisplayId, brightness, isEnabled
        }

        fileprivate var usable: Bool { isEnabled && (0...1).contains(brightness) }
    }

    private struct Request: Encodable {
        let persistentDisplayId: String
        let brightness: Double
    }

    private struct Update: Decodable {
        let persistentDisplayId: String
        let brightness: Double
        let statusCode: Int
    }

    private enum Failure: Error, CustomStringConvertible {
        case unavailable, unconfirmed

        var description: String {
            switch self {
            case .unavailable: return "DisplayLink 백라이트 값을 읽을 수 없음"
            case .unconfirmed: return "DisplayLink가 백라이트 변경을 확인하지 않음"
            }
        }
    }

    private let center = DistributedNotificationCenter.default()
    private let condition = NSCondition()
    private var observers: [NSObjectProtocol] = []
    private var screens: [Screen] = []
    private var listRevision = 0
    private var pendingID: String?
    private var update: Update?

    public var onAvailabilityChange: () -> Void = {}

    public init() {
        observers = [
            observe("DisplayListUpdated") { [weak self] (list: [Screen]) in
                self?.receive(list)
            },
            observe("BrightnessUpdated") { [weak self] (update: Update) in
                self?.receive(update)
            }
        ]
    }

    deinit {
        for observer in observers { center.removeObserver(observer) }
    }

    public func discover() -> [Screen] {
        condition.lock()
        let revision = listRevision
        condition.unlock()
        post("GetDisplays")

        let deadline = Date(timeIntervalSinceNow: 0.28)
        condition.lock()
        defer { condition.unlock() }
        while revision == listRevision && condition.wait(until: deadline) {}
        return revision == listRevision ? [] : screens.filter(\.usable)
    }

    public func read(_ screen: Screen) throws -> Double {
        guard let actual = discover().first(where: {
            $0.displayID == screen.displayID && $0.persistentDisplayId == screen.persistentDisplayId
        }) else { throw Failure.unavailable }
        return actual.brightness
    }

    public func write(_ level: Double, to screen: Screen) throws -> Double {
        let payload = try JSONEncoder().encode(Request(persistentDisplayId: screen.persistentDisplayId,
                                                       brightness: level))
        condition.lock()
        pendingID = screen.persistentDisplayId
        update = nil
        condition.unlock()
        post("SetBrightness", object: String(decoding: payload, as: UTF8.self))

        let deadline = Date(timeIntervalSinceNow: 0.35)
        condition.lock()
        while update == nil && condition.wait(until: deadline) {}
        let response = update
        pendingID = nil
        update = nil
        condition.unlock()

        if let response, response.statusCode == 0,
           (0...1).contains(response.brightness), abs(response.brightness - level) <= 0.01 {
            return response.brightness
        }
        if let actual = try? read(screen), abs(actual - level) <= 0.01 { return actual }
        throw Failure.unconfirmed
    }

    private func receive(_ newScreens: [Screen]) {
        condition.lock()
        let before = availableIDs
        screens = newScreens
        listRevision += 1
        let availabilityChanged = before != availableIDs
        condition.broadcast()
        condition.unlock()
        if availabilityChanged { onAvailabilityChange() }
    }

    private func receive(_ received: Update) {
        condition.lock()
        let before = availableIDs
        if received.statusCode == 0, (0...1).contains(received.brightness),
           let index = screens.firstIndex(where: { $0.persistentDisplayId == received.persistentDisplayId }) {
            screens[index].brightness = received.brightness
        }
        if received.persistentDisplayId == pendingID { update = received }
        let availabilityChanged = before != availableIDs
        condition.broadcast()
        condition.unlock()
        if availabilityChanged { onAvailabilityChange() }
    }

    // Read while holding the condition lock.
    private var availableIDs: Set<CGDirectDisplayID> {
        Set(screens.filter(\.usable).map(\.displayID))
    }

    private func observe<T: Decodable>(_ suffix: String, receive: @escaping (T) -> Void) -> NSObjectProtocol {
        let observer = ImmediateDisplayLinkObserver { note in
            guard let payload = note.object as? String,
                  let decoded = try? JSONDecoder().decode(T.self, from: Data(payload.utf8)) else { return }
            receive(decoded)
        }
        // A background menu-bar app can have distributed notifications
        // suspended. Hardware replies must reach an in-flight request now.
        center.addObserver(observer, selector: #selector(ImmediateDisplayLinkObserver.receive(_:)),
                           name: .init("com.displaylink." + suffix), object: nil,
                           suspensionBehavior: .deliverImmediately)
        return observer
    }

    private func post(_ suffix: String, object: String? = nil) {
        center.postNotificationName(.init("com.displaylink." + suffix), object: object,
                                    userInfo: nil, deliverImmediately: true)
    }
}

private final class ImmediateDisplayLinkObserver: NSObject {
    private let handle: (Notification) -> Void

    init(handle: @escaping (Notification) -> Void) {
        self.handle = handle
    }

    @objc func receive(_ note: Notification) {
        DispatchQueue.main.async { self.handle(note) }
    }
}
