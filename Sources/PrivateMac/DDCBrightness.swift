import Darwin
import Foundation
import IOKit

public final class DDCBrightness {
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> UnsafeRawPointer?
    private typealias Transfer = @convention(c) (UnsafeRawPointer, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> Int32

    private struct API {
        let create: Create
        let read: Transfer
        let write: Transfer

        init?() {
            let path = "/System/Library/Frameworks/IOKit.framework/IOKit"
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
                  let create = dlsym(handle, "IOAVServiceCreateWithService"),
                  let read = dlsym(handle, "IOAVServiceReadI2C"),
                  let write = dlsym(handle, "IOAVServiceWriteI2C") else { return nil }
            self.create = unsafeBitCast(create, to: Create.self)
            self.read = unsafeBitCast(read, to: Transfer.self)
            self.write = unsafeBitCast(write, to: Transfer.self)
        }
    }

    private static let api = API()
    private static let chip: UInt32 = 0x37
    private static let data: UInt32 = 0x51
    private static let luminance: UInt8 = 0x10
    private let api: API
    private let service: UnsafeRawPointer

    public init?(displayLocation: String) {
        guard let api = Self.api, let proxy = Self.externalProxy(for: displayLocation) else { return nil }
        defer { IOObjectRelease(proxy) }
        guard let service = api.create(kCFAllocatorDefault, proxy) else { return nil }
        self.api = api
        self.service = service
    }

    deinit {
        Unmanaged<AnyObject>.fromOpaque(service).release()
    }

    public struct Reading: Equatable {
        public let current: UInt16
        public let maximum: UInt16
        public var level: Double { Double(current) / Double(maximum) }
    }

    public enum Failure: Error, CustomStringConvertible {
        case unavailable, unchanged

        public var description: String {
            switch self {
            case .unavailable: return "모니터가 DDC/CI 밝기 읽기 요청에 응답하지 않음"
            case .unchanged: return "모니터가 DDC/CI 밝기 변경을 확인하지 않음"
            }
        }
    }

    public func read() throws -> Reading {
        var packet: [UInt8] = [0x82, 0x01, Self.luminance]
        packet.append(packet.reduce(0x6E ^ 0x51, ^))
        for _ in 0..<3 {
            // DisplayPort DDC/CI packets are transported by IOAVService as
            // observed in waydabber/AppleSiliconDDC.
            usleep(10_000)
            guard transfer(api.write, bytes: &packet) == 0 else { continue }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 12)
            guard transfer(api.read, bytes: &reply) == 0,
                  reply[0] == 0x6E, reply[1] == 0x88, reply[2] == 0x02,
                  reply[3] == 0, reply[4] == Self.luminance,
                  reply.prefix(10).reduce(0x50, ^) == reply[10] else { continue }
            let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
            guard maximum > 0, current <= maximum else { break }
            return Reading(current: current, maximum: maximum)
        }
        throw Failure.unavailable
    }

    public func write(_ level: Double, from previous: Reading) throws -> Reading {
        guard level.isFinite, (0...1).contains(level), previous.maximum > 0 else { throw Failure.unavailable }
        let requested = UInt16((level * Double(previous.maximum)).rounded())
        if requested == previous.current { return previous }
        var packet: [UInt8] = [0x84, 0x03, Self.luminance, UInt8(requested >> 8), UInt8(requested & 0xff)]
        packet.append(packet.reduce(0x6E ^ 0x51, ^))
        for _ in 0..<2 {
            usleep(10_000)
            guard transfer(api.write, bytes: &packet) == 0 else { continue }
            usleep(50_000)
            if let actual = try? read(), actual.maximum == previous.maximum, actual.current == requested {
                return actual
            }
        }
        throw Failure.unchanged
    }

    private func transfer(_ function: Transfer, bytes: inout [UInt8]) -> Int32 {
        bytes.withUnsafeMutableBytes { buffer in
            function(service, Self.chip, Self.data, buffer.baseAddress, UInt32(buffer.count))
        }
    }

    private static func externalProxy(for location: String) -> io_service_t? {
        let components = location.split(separator: "/")
        guard components.count >= 3, let port = components.dropLast().last?.split(separator: "@").first,
              ["AppleCLCD2", "IOMobileFramebufferShim"].contains(components.last) else { return nil }
        let prefix = components.dropLast(2).joined(separator: "/") + "/"
        let endpoint = "\(port):dcpav-service-epic:"
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var match: io_service_t?
        while case let candidate = IOIteratorNext(iterator), candidate != 0 {
            guard let location = IORegistryEntryCreateCFProperty(candidate, "Location" as CFString,
                                                                 kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                  location == "External", let path = registryPath(candidate), path.hasPrefix(prefix),
                  path.split(separator: "/").dropLast().last?.hasPrefix(endpoint) == true else {
                IOObjectRelease(candidate)
                continue
            }
            if let match {
                IOObjectRelease(match)
                IOObjectRelease(candidate)
                return nil
            }
            match = candidate
        }
        return match
    }

    private static func registryPath(_ entry: io_registry_entry_t) -> String? {
        var path = [CChar](repeating: 0, count: MemoryLayout<io_string_t>.size)
        guard IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS else { return nil }
        return String(cString: path)
    }
}
