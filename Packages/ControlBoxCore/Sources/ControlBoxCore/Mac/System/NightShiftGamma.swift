import CoreGraphics
import Foundation

/// Extra amber past Apple's Night Shift floor (2700 K) via per-display gamma.
/// `setCCTRange` / `setCCT` reject anything below `getCCTRange.min`.
public enum NightShiftGamma {
    public static let blueFloor = 0.18

    private static let lock = NSLock()
    private static var owned = false

    public static func rgbScale(warmth: Double) -> (r: Double, g: Double, b: Double) {
        let t = min(max(warmth, 0), 1)
        guard t > 0.004 else { return (1, 1, 1) }
        let apple = blackbodyRGB(NightShift.CCTRange.fallback.minKelvin)
        let extra = blackbodyRGB(NightShift.extraMinKelvin)
        let fullR = extra.r / max(apple.r, 0.001)
        let fullG = extra.g / max(apple.g, 0.001)
        let fullB = max(extra.b / max(apple.b, 0.001), blueFloor)
        return (
            r: 1 + (fullR - 1) * t,
            g: 1 + (fullG - 1) * t,
            b: 1 + (fullB - 1) * t
        )
    }

    public static func apply(warmth: Double) {
        let scale = rgbScale(warmth: warmth)
        if scale.g >= 0.998, scale.b >= 0.998 {
            restore()
            return
        }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return }
        let n = 256
        var red = [CGGammaValue](repeating: 0, count: n)
        var green = [CGGammaValue](repeating: 0, count: n)
        var blue = [CGGammaValue](repeating: 0, count: n)
        let denom = CGGammaValue(max(n - 1, 1))
        for i in 0..<n {
            let x = CGGammaValue(i) / denom
            red[i] = x * CGGammaValue(scale.r)
            green[i] = x * CGGammaValue(scale.g)
            blue[i] = x * CGGammaValue(scale.b)
        }
        for id in ids.prefix(Int(count)) {
            _ = red.withUnsafeBufferPointer { r in
                green.withUnsafeBufferPointer { g in
                    blue.withUnsafeBufferPointer { b in
                        CGSetDisplayTransferByTable(
                            id,
                            UInt32(n),
                            r.baseAddress,
                            g.baseAddress,
                            b.baseAddress
                        )
                    }
                }
            }
        }
        lock.lock()
        owned = true
        lock.unlock()
    }

    public static func restore() {
        lock.lock()
        let shouldRestore = owned
        owned = false
        lock.unlock()
        guard shouldRestore else { return }
        CGDisplayRestoreColorSyncSettings()
    }

    static func blackbodyRGB(_ kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let t = min(max(kelvin, 1000), 10_000) / 100
        var r: Double
        var g: Double
        var b: Double
        if t <= 66 {
            r = 1
            g = (99.4708025861 * log(t) - 161.1195681661) / 255
        } else {
            r = (329.698727446 * pow(t - 60, -0.1332047592)) / 255
            g = (288.1221695283 * pow(t - 60, -0.0755148492)) / 255
        }
        if t >= 66 {
            b = 1
        } else if t <= 19 {
            b = 0
        } else {
            b = (138.5177312231 * log(t - 10) - 305.0447927307) / 255
        }
        return (min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1))
    }
}
