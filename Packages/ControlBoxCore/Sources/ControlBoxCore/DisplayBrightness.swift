import AppKit
import CoreGraphics
import Foundation
import IOKit

/// One attached screen. DDC matching and Apple-silicon I2C follow MonitorControl (MIT).
public struct AttachedDisplay: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var brightness: Double
    public var contrast: Double
    public var canAdjustBrightness: Bool
    public var canAdjustContrast: Bool
    public var isBuiltIn: Bool
    public var isDummy: Bool

    public var canAdjust: Bool { canAdjustBrightness }

    public init(
        id: String,
        name: String,
        detail: String,
        brightness: Double,
        contrast: Double = 1,
        canAdjustBrightness: Bool,
        canAdjustContrast: Bool = false,
        isBuiltIn: Bool,
        isDummy: Bool = false
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.brightness = brightness
        self.contrast = contrast
        self.canAdjustBrightness = canAdjustBrightness
        self.canAdjustContrast = canAdjustContrast
        self.isBuiltIn = isBuiltIn
        self.isDummy = isDummy
    }
}

public enum DisplayBrightness {
    private static let vcpBrightness: UInt8 = 0x10
    private static let vcpContrast: UInt8 = 0x12
    private static let lock = NSLock()
    private static var pipes: [String: Pipe] = [:]

    private struct Pipe {
        var service: OpaquePointer?
        var brightnessMax: UInt16
        var contrastMax: UInt16
        var ioPath: String
    }

    public static func connectedDisplays() -> [AttachedDisplay] {
        let screens = NSScreen.screens.compactMap(screen(_:))
        let ids = screens.map(\.displayID)
        let matches = Arm64DDC.serviceMatches(for: ids)
        var nextPipes: [String: Pipe] = [:]

        let result: [AttachedDisplay] = screens.map { screen in
            if screen.isBuiltIn, let brightness = coreDisplayBrightness(screen.displayID) {
                return AttachedDisplay(
                    id: "cg:\(screen.displayID)",
                    name: screen.name,
                    detail: "Built-in",
                    brightness: brightness,
                    canAdjustBrightness: true,
                    isBuiltIn: true
                )
            }

            if Arm64DDC.isDummyScreen(name: screen.name, displayID: screen.displayID) {
                return AttachedDisplay(
                    id: "cg:\(screen.displayID)",
                    name: screen.name,
                    detail: "Dummy or virtual display — DDC ignored",
                    brightness: 1,
                    canAdjustBrightness: false,
                    isBuiltIn: false,
                    isDummy: true
                )
            }

            let match = matches.first { $0.displayID == screen.displayID }
            if let match, match.dummy || Arm64DDC.isDummy(match.details) {
                return AttachedDisplay(
                    id: "cg:\(screen.displayID)",
                    name: screen.name,
                    detail: "Dummy or virtual display — DDC ignored",
                    brightness: 1,
                    canAdjustBrightness: false,
                    isBuiltIn: false,
                    isDummy: true
                )
            }

            guard let match, let service = match.service else {
                return AttachedDisplay(
                    id: "cg:\(screen.displayID)",
                    name: screen.name,
                    detail: "No DDC on this connection",
                    brightness: 1,
                    canAdjustBrightness: false,
                    isBuiltIn: false
                )
            }

            let key = identityKey(match.details, displayID: screen.displayID)
            let brightness = Arm64DDC.read(service: service, command: vcpBrightness)
            let contrast = Arm64DDC.read(service: service, command: vcpContrast)
            let pipe = Pipe(
                service: service,
                brightnessMax: brightness?.max ?? 0,
                contrastMax: contrast?.max ?? 0,
                ioPath: match.details.ioDisplayLocation
            )
            nextPipes[key] = pipe

            let hardwareBrightness = brightness.flatMap { $0.max > 0 ? Double($0.current) / Double($0.max) : nil } ?? 1
            let hardwareContrast = contrast.flatMap { $0.max > 0 ? Double($0.current) / Double($0.max) : nil } ?? 1
            let remembered = applyRememberedSettings(
                key: key,
                ioPath: pipe.ioPath,
                hardwareBrightness: hardwareBrightness,
                hardwareContrast: hardwareContrast,
                brightnessMax: pipe.brightnessMax,
                contrastMax: pipe.contrastMax,
                service: service
            )

            let serial = match.details.alphanumericSerialNumber.isEmpty
                ? (match.details.serialNumber == 0 ? "" : "\(match.details.serialNumber)")
                : match.details.alphanumericSerialNumber
            let detail = serial.isEmpty ? "DDC/CI" : "DDC · \(serial)"
            return AttachedDisplay(
                id: "mon:\(key)",
                name: screen.name,
                detail: detail,
                brightness: remembered.brightness,
                contrast: remembered.contrast,
                canAdjustBrightness: pipe.brightnessMax > 0,
                canAdjustContrast: pipe.contrastMax > 0,
                isBuiltIn: false
            )
        }

        lock.lock()
        pipes = nextPipes
        lock.unlock()
        return result
    }

    public static func setBrightness(_ value: Double, id: String) {
        setVCP(value, id: id, vcp: vcpBrightness, maxKey: \.brightnessMax, saved: \.brightness)
    }

    public static func setContrast(_ value: Double, id: String) {
        setVCP(value, id: id, vcp: vcpContrast, maxKey: \.contrastMax, saved: \.contrast)
    }

    private static func setVCP(
        _ value: Double,
        id: String,
        vcp: UInt8,
        maxKey: KeyPath<Pipe, UInt16>,
        saved: WritableKeyPath<MonitorSettings.Record, Double>
    ) {
        let clamped = min(max(value, 0), 1)
        if vcp == vcpBrightness, id.hasPrefix("cg:"), let displayID = UInt32(String(id.dropFirst(3))) {
            setCoreDisplayBrightness(displayID, clamped)
            return
        }
        guard id.hasPrefix("mon:") else { return }
        let key = String(id.dropFirst(4))
        lock.lock()
        let pipe = pipes[key]
        lock.unlock()
        guard let pipe, let service = pipe.service else { return }
        let scale = max(pipe[keyPath: maxKey], 1)
        let native = UInt16((clamped * Double(scale)).rounded())
        guard Arm64DDC.write(service: service, command: vcp, value: native) else { return }
        var record = MonitorSettings.record(for: key) ?? MonitorSettings.Record(
            brightness: clamped,
            contrast: clamped,
            ioPath: pipe.ioPath
        )
        record[keyPath: saved] = clamped
        record.ioPath = pipe.ioPath
        MonitorSettings.save(record, for: key)
    }

    private static func applyRememberedSettings(
        key: String,
        ioPath: String,
        hardwareBrightness: Double,
        hardwareContrast: Double,
        brightnessMax: UInt16,
        contrastMax: UInt16,
        service: OpaquePointer?
    ) -> (brightness: Double, contrast: Double) {
        guard let saved = MonitorSettings.record(for: key) else {
            MonitorSettings.save(
                MonitorSettings.Record(brightness: hardwareBrightness, contrast: hardwareContrast, ioPath: ioPath),
                for: key
            )
            return (hardwareBrightness, hardwareContrast)
        }
        if saved.ioPath != ioPath {
            if brightnessMax > 0 {
                _ = Arm64DDC.write(
                    service: service,
                    command: vcpBrightness,
                    value: UInt16((saved.brightness * Double(brightnessMax)).rounded())
                )
            }
            if contrastMax > 0 {
                _ = Arm64DDC.write(
                    service: service,
                    command: vcpContrast,
                    value: UInt16((saved.contrast * Double(contrastMax)).rounded())
                )
            }
            var record = saved
            record.ioPath = ioPath
            MonitorSettings.save(record, for: key)
            return (saved.brightness, saved.contrast)
        }
        return (hardwareBrightness, hardwareContrast)
    }

    /// Stable per-panel id: alphanumeric serial when present, else numeric serial, else EDID UUID.
    private static func identityKey(_ details: Arm64DDC.IORegService, displayID: CGDirectDisplayID) -> String {
        if !details.alphanumericSerialNumber.isEmpty {
            return "\(details.manufacturerID)-\(details.productName)-\(details.alphanumericSerialNumber)"
        }
        if details.serialNumber != 0 {
            return "\(details.serialNumber)"
        }
        if !details.edidUUID.isEmpty {
            return details.edidUUID
        }
        if !details.ioDisplayLocation.isEmpty {
            return details.ioDisplayLocation
        }
        return "cg-\(displayID)"
    }

    private struct Screen {
        var displayID: CGDirectDisplayID
        var name: String
        var isBuiltIn: Bool
    }

    private static func screen(_ ns: NSScreen) -> Screen? {
        guard let number = ns.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(truncating: number)
        return Screen(
            displayID: displayID,
            name: ns.localizedName,
            isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
        )
    }

    private static func coreDisplayBrightness(_ displayID: CGDirectDisplayID) -> Double? {
        guard let get = CoreDisplayLink.get else { return nil }
        let value = get(displayID)
        guard value.isFinite, value >= 0, value <= 1 else { return nil }
        return value
    }

    private static func setCoreDisplayBrightness(_ displayID: CGDirectDisplayID, _ value: Double) {
        CoreDisplayLink.set?(displayID, value)
    }
}

private enum MonitorSettings {
    static let defaultsKey = "controlbox.monitorSettings.v1"

    struct Record: Codable {
        var brightness: Double
        var contrast: Double
        var ioPath: String
    }

    static func record(for key: String) -> Record? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let all = try? JSONDecoder().decode([String: Record].self, from: data) else {
            return nil
        }
        return all[key]
    }

    static func save(_ record: Record, for key: String) {
        var all: [String: Record] = [:]
        if let data = UserDefaults.standard.data(forKey: defaultsKey) {
            all = (try? JSONDecoder().decode([String: Record].self, from: data)) ?? [:]
        }
        all[key] = record
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

private enum CoreDisplayLink {
    typealias Get = @convention(c) (CGDirectDisplayID) -> Double
    typealias Set = @convention(c) (CGDirectDisplayID, Double) -> Void
    static let get: Get? = load("CoreDisplay_Display_GetUserBrightness")
    static let set: Set? = load("CoreDisplay_Display_SetUserBrightness")

    private static func load<T>(_ name: String) -> T? {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            RTLD_LAZY
        ), let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}
