import CoreGraphics
import Foundation

@objc private protocol BrightnessOSDService {
    func showImage(_ image: Int64, onDisplayID display: UInt32, priority: UInt32,
                   msecUntilFade: UInt32, filledChiclets: UInt32, totalChiclets: UInt32,
                   locked: Bool)
}

// Apple's OSD service presents an indicator without sending a brightness key
// or changing a display. All connection state belongs to the main queue.
public final class SystemBrightnessFeedback {
    private var connection: NSXPCConnection?
    public var onFailure: () -> Void = {}

    public init() {}

    deinit { connection?.invalidate() }

    public func show(_ level: Double, on display: CGDirectDisplayID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard level.isFinite, (0...1).contains(level), CGDisplayIsActive(display) != 0 else { return }

        let service: NSXPCConnection
        if let connection {
            service = connection
        } else {
            service = NSXPCConnection(machServiceName: "com.apple.OSDUIHelper", options: [])
            service.remoteObjectInterface = NSXPCInterface(with: BrightnessOSDService.self)
            service.interruptionHandler = { [weak self, weak service] in self?.failed(service) }
            service.invalidationHandler = { [weak self, weak service] in self?.failed(service) }
            connection = service
            service.resume()
        }

        let proxy = service.remoteObjectProxyWithErrorHandler { [weak self, weak service] _ in
            self?.failed(service)
        }
        guard let osd = proxy as? BrightnessOSDService else { failed(service); return }
        osd.showImage(1, onDisplayID: display, priority: 500, msecUntilFade: 1000,
                      filledChiclets: UInt32((level * 100).rounded()), totalChiclets: 100, locked: false)
    }

    private func failed(_ service: NSXPCConnection?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let service, self.connection === service else { return }
            self.connection = nil
            service.interruptionHandler = nil
            service.invalidationHandler = nil
            service.invalidate()
            self.onFailure()
        }
    }
}
