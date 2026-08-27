import Darwin
import Foundation

/// Drives system Night Shift (`CBBlueLightClient` in CoreBrightness).
/// Loaded at runtime; the private framework is not linked.
public enum NightShift {
    public struct Snapshot: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var mode: Int32
        public var strength: Float
    }

    public struct CCTRange: Equatable, Sendable {
        public var minKelvin: Double
        public var maxKelvin: Double

        public static let fallback = CCTRange(minKelvin: 2700, maxKelvin: 6000)
    }

    /// Apple's schedule modes. `off` keeps Night Shift available but stops
    /// sunset / custom clocks from fighting a curve we apply ourselves.
    public enum Mode: Int32, Sendable {
        case sunSchedule = 0
        case off = 1
        case customSchedule = 2
    }

    public static var isSupported: Bool {
        Client.shared.isSupported
    }

    public static func snapshot() -> Snapshot? {
        Client.shared.snapshot()
    }

    public static func restore(_ snapshot: Snapshot) {
        Client.shared.restore(snapshot)
    }

    public static func cctRange() -> CCTRange {
        Client.shared.cctRange() ?? .fallback
    }

    /// Pause Apple's Night Shift schedule so strength follows our curve.
    public static func takeOverSchedule() {
        Client.shared.setMode(.off)
    }

    /// `warmth` is 0…1 (cool → Night Shift maximum). Near-zero turns Night Shift off
    /// so the panel is full daylight. `period` is the CoreBrightness fade in seconds.
    public static func apply(warmth: Double, period: TimeInterval) {
        Client.shared.apply(warmth: warmth, period: period)
    }
}

private final class Client: @unchecked Sendable {
    static let shared = Client()

    private let lock = NSLock()
    private let framework = dlopen(
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
        RTLD_LAZY
    )
    private var object: NSObject?
    private var supported = false

    var isSupported: Bool {
        lock.lock()
        defer { lock.unlock() }
        return supported
    }

    init() {
        _ = framework
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return }
        if cls.responds(to: NSSelectorFromString("supportsBlueLightReduction")) {
            typealias Fn = @convention(c) (AnyClass, Selector) -> Bool
            let sel = NSSelectorFromString("supportsBlueLightReduction")
            guard let method = cls.method(for: sel),
                  unsafeBitCast(method, to: Fn.self)(cls, sel) else { return }
        }
        let client = cls.init()
        object = client
        supported = client.responds(to: NSSelectorFromString("setStrength:commit:"))
            && client.responds(to: NSSelectorFromString("setEnabled:"))
    }

    func snapshot() -> NightShift.Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let object, let strength = strength(object) else { return nil }
        let status = status(object)
        return NightShift.Snapshot(
            enabled: status.enabled,
            mode: status.mode,
            strength: strength
        )
    }

    func restore(_ snapshot: NightShift.Snapshot) {
        lock.lock()
        defer { lock.unlock() }
        guard let object else { return }
        setMode(object, snapshot.mode)
        setEnabled(object, snapshot.enabled)
        setStrength(object, snapshot.strength, period: 0.8)
    }

    func cctRange() -> NightShift.CCTRange? {
        lock.lock()
        defer { lock.unlock() }
        guard let object else { return nil }
        let sel = NSSelectorFromString("getCCTRange:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return nil }
        var range = (min: Float(0), max: Float(0), mid: Float(0))
        typealias Fn = @convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Bool
        let ok = withUnsafeMutablePointer(to: &range) {
            unsafeBitCast(method, to: Fn.self)(object, sel, $0)
        }
        guard ok, range.max > range.min, range.min > 500, range.max < 12_000 else { return nil }
        return NightShift.CCTRange(minKelvin: Double(range.min), maxKelvin: Double(range.max))
    }

    func setMode(_ mode: NightShift.Mode) {
        lock.lock()
        defer { lock.unlock() }
        guard let object else { return }
        setMode(object, mode.rawValue)
    }

    func apply(warmth: Double, period: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard let object else { return }
        let clamped = Float(min(max(warmth, 0), 1))
        if clamped < 0.012 {
            setEnabled(object, false)
            return
        }
        setEnabled(object, true)
        setStrength(object, clamped, period: period)
    }

    private func strength(_ object: NSObject) -> Float? {
        let sel = NSSelectorFromString("getStrength:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return nil }
        var value: Float = 0
        typealias Fn = @convention(c) (NSObject, Selector, UnsafeMutablePointer<Float>) -> Bool
        let ok = unsafeBitCast(method, to: Fn.self)(object, sel, &value)
        return ok ? value : nil
    }

    private func status(_ object: NSObject) -> (enabled: Bool, mode: Int32) {
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard object.responds(to: sel), let method = object.method(for: sel) else {
            return (false, NightShift.Mode.off.rawValue)
        }
        var buf = [UInt8](repeating: 0, count: 64)
        typealias Fn = @convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Bool
        let ok = buf.withUnsafeMutableBytes {
            unsafeBitCast(method, to: Fn.self)(object, sel, $0.baseAddress!)
        }
        guard ok else { return (false, NightShift.Mode.off.rawValue) }
        let enabled = buf[1] != 0
        let mode = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int32.self) }
        return (enabled, mode)
    }

    private func setEnabled(_ object: NSObject, _ enabled: Bool) {
        let sel = NSSelectorFromString("setEnabled:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return }
        typealias Fn = @convention(c) (NSObject, Selector, Bool) -> Bool
        _ = unsafeBitCast(method, to: Fn.self)(object, sel, enabled)
    }

    private func setMode(_ object: NSObject, _ mode: Int32) {
        let sel = NSSelectorFromString("setMode:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return }
        typealias Fn = @convention(c) (NSObject, Selector, Int32) -> Bool
        _ = unsafeBitCast(method, to: Fn.self)(object, sel, mode)
    }

    private func setStrength(_ object: NSObject, _ strength: Float, period: TimeInterval) {
        if period > 0.04, object.responds(to: NSSelectorFromString("setStrength:withPeriod:commit:")) {
            let sel = NSSelectorFromString("setStrength:withPeriod:commit:")
            guard let method = object.method(for: sel) else { return }
            typealias Fn = @convention(c) (NSObject, Selector, Float, Float, Bool) -> Bool
            _ = unsafeBitCast(method, to: Fn.self)(object, sel, strength, Float(period), true)
            return
        }
        let sel = NSSelectorFromString("setStrength:commit:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return }
        typealias Fn = @convention(c) (NSObject, Selector, Float, Bool) -> Bool
        _ = unsafeBitCast(method, to: Fn.self)(object, sel, strength, true)
    }
}
