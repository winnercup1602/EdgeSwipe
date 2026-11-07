import Foundation
import Darwin
import ObjectiveC

public final class KeyboardBrightness {
    private typealias Read = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias BuiltIn = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias Write = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private let client: NSObject
    private let keyboard: UInt64
    private let getter: Read
    private let setter: Write
    private let readSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let writeSelector = NSSelectorFromString("setBrightness:forKeyboard:")

    public init?() {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard dlopen(path, RTLD_NOW | RTLD_LOCAL) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let object = type.init()
        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard object.responds(to: idsSelector),
              let ids = object.perform(idsSelector)?.takeRetainedValue() as? [NSNumber],
              let first = ids.first,
              let read = class_getInstanceMethod(type, readSelector),
              let write = class_getInstanceMethod(type, writeSelector),
              let readEncoding = method_getTypeEncoding(read), String(cString: readEncoding).hasPrefix("f"),
              let writeEncoding = method_getTypeEncoding(write), String(cString: writeEncoding).hasPrefix("B") else { return nil }
        client = object
        let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
        if let method = class_getInstanceMethod(type, builtInSelector),
           let encoding = method_getTypeEncoding(method), String(cString: encoding).hasPrefix("B") {
            let isBuiltIn = unsafeBitCast(method_getImplementation(method), to: BuiltIn.self)
            keyboard = ids.first(where: { isBuiltIn(object, builtInSelector, $0.uint64Value) })?.uint64Value ?? first.uint64Value
        } else { keyboard = first.uint64Value }
        getter = unsafeBitCast(method_getImplementation(read), to: Read.self)
        setter = unsafeBitCast(method_getImplementation(write), to: Write.self)
        guard (try? self.read()) != nil else { return nil }
    }

    public func read() throws -> Double {
        let level = Double(getter(client, readSelector, keyboard))
        guard level.isFinite, (0...1).contains(level) else { throw Failure.unavailable }
        return level
    }

    public func write(_ level: Double) throws -> Double {
        guard level.isFinite, (0...1).contains(level), setter(client, writeSelector, Float(level), keyboard) else {
            throw Failure.unavailable
        }
        for _ in 0..<10 {
            let actual = try read()
            if abs(actual - level) <= 0.01 { return actual }
            Thread.sleep(forTimeInterval: 0.015)
        }
        throw Failure.unconfirmed
    }

    public enum Failure: Error, CustomStringConvertible {
        case unavailable, unconfirmed
        public var description: String {
            self == .unavailable ? "키보드 백라이트를 사용할 수 없음" : "키보드 밝기 변경을 확인하지 못함"
        }
    }
}
