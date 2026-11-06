import CoreGraphics
import Darwin

public final class NativeBrightness {
    private typealias Read = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

    private let readFunction: Read

    public init?() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
              let read = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        readFunction = unsafeBitCast(read, to: Read.self)
    }

    public func read(display: CGDirectDisplayID) throws -> Double {
        var value: Float = 0
        let status = readFunction(display, &value)
        guard status == 0 else { throw Failure(status: status) }
        return Double(value)
    }

    public struct Failure: Error {
        public let status: Int32
    }
}
