import Darwin
import Foundation

/// Drives system Night Shift (`CBBlueLightClient` in CoreBrightness).
/// Loaded at runtime; the private framework is not linked.
public enum NightShift {
    public struct Snapshot: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var mode: Int32
        public var strength: Float
        public var fromHour: Int32
        public var fromMinute: Int32
        public var toHour: Int32
        public var toMinute: Int32

        public init(
            enabled: Bool,
            mode: Int32,
            strength: Float,
            fromHour: Int32 = 0,
            fromMinute: Int32 = 0,
            toHour: Int32 = 0,
            toMinute: Int32 = 0
        ) {
            self.enabled = enabled
            self.mode = mode
            self.strength = strength
            self.fromHour = fromHour
            self.fromMinute = fromMinute
            self.toHour = toHour
            self.toMinute = toMinute
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decode(Bool.self, forKey: .enabled)
            mode = try container.decode(Int32.self, forKey: .mode)
            strength = try container.decode(Float.self, forKey: .strength)
            fromHour = try container.decodeIfPresent(Int32.self, forKey: .fromHour) ?? 0
            fromMinute = try container.decodeIfPresent(Int32.self, forKey: .fromMinute) ?? 0
            toHour = try container.decodeIfPresent(Int32.self, forKey: .toHour) ?? 0
            toMinute = try container.decodeIfPresent(Int32.self, forKey: .toMinute) ?? 0
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enabled, forKey: .enabled)
            try container.encode(mode, forKey: .mode)
            try container.encode(strength, forKey: .strength)
            try container.encode(fromHour, forKey: .fromHour)
            try container.encode(fromMinute, forKey: .fromMinute)
            try container.encode(toHour, forKey: .toHour)
            try container.encode(toMinute, forKey: .toMinute)
        }

        private enum CodingKeys: String, CodingKey {
            case enabled, mode, strength, fromHour, fromMinute, toHour, toMinute
        }
    }

    public struct CCTRange: Equatable, Sendable {
        public var minKelvin: Double
        public var maxKelvin: Double

        public static let fallback = CCTRange(minKelvin: 2700, maxKelvin: 6000)
    }

    /// Apple's schedule modes. Tahoe rejects `off` (`setMode:1` returns false and
    /// leaves sunset-to-sunrise in place), so take-over uses a 24-hour custom schedule.
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
        Client.shared.takeOverSchedule()
    }

    /// Called when System Settings / Control Center changes Night Shift.
    /// The handler is invoked on the main queue.
    public static func setStatusHandler(_ handler: (@Sendable () -> Void)?) {
        Client.shared.setStatusHandler(handler)
    }

    /// `warmth` is 0…1 (cool → Night Shift maximum). Near-zero turns Night Shift off
    /// so the panel is full daylight. `period` is the CoreBrightness fade in seconds.
    /// `restyle` writes the 24-hour take-over schedule; live curve drags skip it
    /// and skip the status XPC that beachballs the pane.
    public static func apply(warmth: Double, period: TimeInterval, restyle: Bool = true) {
        Client.shared.apply(warmth: warmth, period: period, restyle: restyle)
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
    private var statusHandler: (@Sendable () -> Void)?
    private var retainedStatusBlock: Any?

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
            strength: strength,
            fromHour: status.fromHour,
            fromMinute: status.fromMinute,
            toHour: status.toHour,
            toMinute: status.toMinute
        )
    }

    func restore(_ snapshot: NightShift.Snapshot) {
        lock.lock()
        defer { lock.unlock() }
        guard let object else { return }
        if snapshot.toHour != 0 || snapshot.toMinute != 0 || snapshot.fromHour != 0 {
            setSchedule(object, fromHour: snapshot.fromHour, fromMinute: snapshot.fromMinute, toHour: snapshot.toHour, toMinute: snapshot.toMinute)
        }
        setMode(object, snapshot.mode)
        setEnabled(object, snapshot.enabled)
        setStrength(object, snapshot.strength, period: 0.8)
    }

    func cctRange() -> NightShift.CCTRange? {
        lock.lock()
        defer { lock.unlock() }
        return cctRangeLocked()
    }

    func takeOverSchedule() {
        lock.lock()
        defer { lock.unlock() }
        takeOverScheduleLocked()
    }

    func setStatusHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        statusHandler = handler
        guard let object else { return }
        let sel = NSSelectorFromString("setStatusNotificationBlock:")
        if handler != nil, object.responds(to: sel), let method = object.method(for: sel) {
            let block: @convention(block) () -> Void = { [weak self] in
                DispatchQueue.main.async {
                    self?.statusHandler?()
                }
            }
            retainedStatusBlock = block
            typealias Fn = @convention(c) (NSObject, Selector, Any) -> Void
            unsafeBitCast(method, to: Fn.self)(object, sel, block)
            callVoid(object, "enableNotifications")
        } else {
            retainedStatusBlock = nil
            if object.responds(to: sel), let method = object.method(for: sel) {
                typealias Fn = @convention(c) (NSObject, Selector, Any?) -> Void
                unsafeBitCast(method, to: Fn.self)(object, sel, nil)
            }
            callVoid(object, "disableNotifications")
        }
    }

    func apply(warmth: Double, period: TimeInterval, restyle: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let object else { return }
        let clamped = Float(min(max(warmth, 0), 1))
        if restyle, isHolding(object, warmth: clamped) {
            return
        }
        if clamped < 0.012 {
            setEnabled(object, false)
            return
        }
        if restyle {
            takeOverScheduleLocked()
            setActive(object, true)
            setEnabled(object, true)
        }
        setStrength(object, clamped, period: period)
        if let range = cctRangeLocked() {
            let kelvin = Float(range.maxKelvin - Double(clamped) * (range.maxKelvin - range.minKelvin))
            setCCT(object, kelvin, period: period)
        }
    }

    private func takeOverScheduleLocked() {
        guard let object else { return }
        setSchedule(object, fromHour: 0, fromMinute: 0, toHour: 23, toMinute: 59)
        if !setMode(object, NightShift.Mode.customSchedule.rawValue) {
            _ = setMode(object, NightShift.Mode.off.rawValue)
        }
        setActive(object, true)
    }

    private func isHolding(_ object: NSObject, warmth: Float) -> Bool {
        let current = status(object)
        if warmth < 0.012 {
            return !current.enabled
        }
        let strengthMatch = abs((strength(object) ?? -1) - warmth) < 0.03
        return current.enabled
            && current.mode == NightShift.Mode.customSchedule.rawValue
            && current.fromHour == 0
            && current.fromMinute == 0
            && current.toHour == 23
            && current.toMinute == 59
            && strengthMatch
    }

    private func callVoid(_ object: NSObject, _ name: String) {
        let sel = NSSelectorFromString(name)
        guard object.responds(to: sel), let method = object.method(for: sel) else { return }
        typealias Fn = @convention(c) (NSObject, Selector) -> Void
        unsafeBitCast(method, to: Fn.self)(object, sel)
    }

    private func cctRangeLocked() -> NightShift.CCTRange? {
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

    private func strength(_ object: NSObject) -> Float? {
        let sel = NSSelectorFromString("getStrength:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return nil }
        var value: Float = 0
        typealias Fn = @convention(c) (NSObject, Selector, UnsafeMutablePointer<Float>) -> Bool
        let ok = unsafeBitCast(method, to: Fn.self)(object, sel, &value)
        return ok ? value : nil
    }

    private func status(_ object: NSObject) -> (
        enabled: Bool,
        mode: Int32,
        fromHour: Int32,
        fromMinute: Int32,
        toHour: Int32,
        toMinute: Int32
    ) {
        let fallback = (false, NightShift.Mode.off.rawValue, Int32(0), Int32(0), Int32(0), Int32(0))
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard object.responds(to: sel), let method = object.method(for: sel) else {
            return fallback
        }
        var buf = [UInt8](repeating: 0, count: 64)
        typealias Fn = @convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Bool
        let ok = buf.withUnsafeMutableBytes {
            unsafeBitCast(method, to: Fn.self)(object, sel, $0.baseAddress!)
        }
        guard ok else { return fallback }
        let mode = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int32.self) }
        let fromHour = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: Int32.self) }
        let fromMinute = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: Int32.self) }
        let toHour = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: Int32.self) }
        let toMinute = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 20, as: Int32.self) }
        return (buf[1] != 0, mode, fromHour, fromMinute, toHour, toMinute)
    }

    private func setEnabled(_ object: NSObject, _ enabled: Bool) {
        let sel = NSSelectorFromString("setEnabled:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return }
        typealias Fn = @convention(c) (NSObject, Selector, Bool) -> Bool
        _ = unsafeBitCast(method, to: Fn.self)(object, sel, enabled)
    }

    @discardableResult
    private func setMode(_ object: NSObject, _ mode: Int32) -> Bool {
        let sel = NSSelectorFromString("setMode:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return false }
        typealias Fn = @convention(c) (NSObject, Selector, Int32) -> Bool
        return unsafeBitCast(method, to: Fn.self)(object, sel, mode)
    }

    private func setActive(_ object: NSObject, _ active: Bool) {
        let sel = NSSelectorFromString("setActive:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return }
        typealias Fn = @convention(c) (NSObject, Selector, Bool) -> Bool
        _ = unsafeBitCast(method, to: Fn.self)(object, sel, active)
    }

    private func setSchedule(
        _ object: NSObject,
        fromHour: Int32,
        fromMinute: Int32,
        toHour: Int32,
        toMinute: Int32
    ) {
        let sel = NSSelectorFromString("setSchedule:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return }
        var schedule = (fromHour, fromMinute, toHour, toMinute)
        typealias Fn = @convention(c) (NSObject, Selector, UnsafeRawPointer) -> Bool
        _ = withUnsafePointer(to: &schedule) {
            unsafeBitCast(method, to: Fn.self)(object, sel, $0)
        }
    }

    private func setStrength(_ object: NSObject, _ strength: Float, period: TimeInterval) {
        if period > 0.04, object.responds(to: NSSelectorFromString("setStrength:withPeriod:commit:")) {
            let sel = NSSelectorFromString("setStrength:withPeriod:commit:")
            if let method = object.method(for: sel) {
                typealias Fn = @convention(c) (NSObject, Selector, Float, Float, Bool) -> Bool
                _ = unsafeBitCast(method, to: Fn.self)(object, sel, strength, Float(period), true)
            }
        }
        let sel = NSSelectorFromString("setStrength:commit:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return }
        typealias Fn = @convention(c) (NSObject, Selector, Float, Bool) -> Bool
        _ = unsafeBitCast(method, to: Fn.self)(object, sel, strength, true)
    }

    private func setCCT(_ object: NSObject, _ kelvin: Float, period: TimeInterval) {
        if period > 0.04, object.responds(to: NSSelectorFromString("setCCT:withPeriod:commit:")) {
            let sel = NSSelectorFromString("setCCT:withPeriod:commit:")
            if let method = object.method(for: sel) {
                typealias Fn = @convention(c) (NSObject, Selector, Float, Float, Bool) -> Bool
                _ = unsafeBitCast(method, to: Fn.self)(object, sel, kelvin, Float(period), true)
            }
        }
        let sel = NSSelectorFromString("setCCT:commit:")
        guard object.responds(to: sel), let method = object.method(for: sel) else { return }
        typealias Fn = @convention(c) (NSObject, Selector, Float, Bool) -> Bool
        _ = unsafeBitCast(method, to: Fn.self)(object, sel, kelvin, true)
    }
}
