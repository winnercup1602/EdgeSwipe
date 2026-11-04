import CoreGraphics
import Darwin

public final class NativeBrightness {
    private typealias Read = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Write = @convention(c) (UInt32, Float) -> Int32

    private let readFunction: Read
    private let writeFunction: Write

    public init?() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
              let read = dlsym(handle, "DisplayServicesGetBrightness"),
              let write = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        readFunction = unsafeBitCast(read, to: Read.self)
        writeFunction = unsafeBitCast(write, to: Write.self)
    }

    public func read(display: CGDirectDisplayID) throws -> Double {
        var value: Float = 0
        let status = readFunction(display, &value)
        guard status == 0 else { throw Failure(status: status) }
        return Double(value)
    }

    public func write(_ level: Double, display: CGDirectDisplayID) throws {
        let status = writeFunction(display, Float(level))
        guard status == 0 else { throw Failure(status: status) }
    }

    public struct Failure: Error {
        public let status: Int32
    }
}
