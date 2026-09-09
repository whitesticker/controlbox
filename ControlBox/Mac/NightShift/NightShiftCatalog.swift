import AppKit
import ControlBoxCore
import Foundation
import Observation

@Observable
@MainActor
final class NightShiftCatalog {
    static let defaultBrightnessSwing = 0.10

    var enabled = false
    var curve = NightShiftCurve.factory
    var isSupported = false
    var range = NightShift.CCTRange.fallback
    var currentWarmth = 0.0
    var adjustExternalBrightness = false
    var brightnessSwing = NightShiftCatalog.defaultBrightnessSwing
    var appearanceSchedule = AppearanceSchedule.factory

    private weak var displayCatalog: DisplayCatalog?
    private var brightnessBaselines: [String: Double] = [:]
    private var snapshot: NightShift.Snapshot?
    private var appearanceSnapshot: MacAppearance.Snapshot?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastApplied: Double?
    private var lastBrightnessOffset: Double?
    private var ignoreSystemUntil = Date.distantPast
    private var lastLiveApply = Date.distantPast
    private var lastAppearanceDark: Bool?
    private static let defaultsKey = "controlbox.nightShift.v1"
    private static let tickInterval: TimeInterval = 20

    init() {
        load()
        isSupported = NightShift.isSupported
        range = NightShift.cctRange()
        currentWarmth = curve.warmth(at: Date())
        observe()
        if enabled, isSupported {
            beginControl(applyImmediately: true)
        }
    }

    func attachDisplays(_ catalog: DisplayCatalog) {
        displayCatalog = catalog
        catalog.onUserBrightnessChange = { [weak self] id, value in
            self?.noteUserBrightness(id: id, value: value)
        }
        catalog.onDisplaysChanged = { [weak self] in
            self?.applyExternalBrightness(force: false)
        }
        if enabled, adjustExternalBrightness {
            applyExternalBrightness(force: true)
        }
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        guard !on || isSupported else { return }
        enabled = on
        persist()
        if on {
            beginControl(applyImmediately: true)
        } else {
            restoreExternalBrightness()
            endControl(restore: true)
        }
    }

    func setAdjustExternalBrightness(_ on: Bool) {
        guard on != adjustExternalBrightness else { return }
        if on {
            captureBaselines()
            adjustExternalBrightness = true
            persist()
            if enabled {
                applyExternalBrightness(force: true)
            }
        } else {
            restoreExternalBrightness()
            adjustExternalBrightness = false
            brightnessBaselines = [:]
            lastBrightnessOffset = nil
            persist()
        }
    }

    func setAppearanceScheduleEnabled(_ on: Bool) {
        guard on != appearanceSchedule.enabled else { return }
        appearanceSchedule.enabled = on
        persist()
        applyAppearanceAfterEdit(scheduling: on)
    }

    func setAppearanceScheduleMode(_ mode: AppearanceScheduleMode) {
        guard mode != appearanceSchedule.mode else { return }
        appearanceSchedule.mode = mode
        persist()
        applyAppearanceAfterEdit(scheduling: appearanceSchedule.enabled)
    }

    func setAppearanceDarkFrom(_ date: Date) {
        appearanceSchedule.darkFromMinutes = NightShiftCurve.minutes(from: date)
        persist()
        applyAppearanceAfterEdit(scheduling: appearanceSchedule.enabled)
    }

    func setAppearanceDarkTo(_ date: Date) {
        appearanceSchedule.darkToMinutes = NightShiftCurve.minutes(from: date)
        persist()
        applyAppearanceAfterEdit(scheduling: appearanceSchedule.enabled)
    }

    func setBrightnessSwing(_ value: Double) {
        brightnessSwing = min(max(value, 0), 0.5)
        persist()
        if enabled, adjustExternalBrightness {
            applyExternalBrightness(force: true)
        }
    }

    func noteUserBrightness(id: String, value: Double) {
        guard enabled, adjustExternalBrightness else { return }
        guard let display = displayCatalog?.displays.first(where: { $0.id == id }),
              !display.isBuiltIn else { return }
        brightnessBaselines[id] = min(max(value - brightnessOffset, 0), 1)
        persist()
    }

    func resetCurve() {
        curve = .factory
        persist()
        apply(period: 1.2, force: true)
    }

    func movePoint(id: String, minutes: Double, warmth: Double, live: Bool) {
        curve.move(id: id, minutes: minutes, warmth: warmth)
        currentWarmth = curve.warmth(at: Date())
        if live {
            let now = Date()
            guard now.timeIntervalSince(lastLiveApply) >= 0.15 else { return }
            lastLiveApply = now
            apply(period: 0.18, force: true, restyle: false)
        } else {
            apply(period: 1.4, force: true)
            persist()
        }
    }

    func addPoint(minutes: Double, warmth: Double) {
        if curve.add(minutes: minutes, warmth: warmth) != nil {
            persist()
            apply(period: 0.6, force: true)
        }
    }

    func removePoint(id: String) {
        if curve.remove(id: id) {
            persist()
            apply(period: 0.6, force: true)
        }
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        NightShift.setStatusHandler(nil)
    }

    private func beginControl(applyImmediately: Bool) {
        if snapshot == nil {
            snapshot = NightShift.snapshot()
        }
        if appearanceSnapshot == nil {
            appearanceSnapshot = MacAppearance.snapshot()
        }
        persist()
        syncAppearance(force: true)
        NightShift.takeOverSchedule()
        NightShift.setStatusHandler { [weak self] in
            Task { @MainActor in
                self?.handleSystemNightShiftChanged()
            }
        }
        startTimer()
        if applyImmediately {
            apply(period: 1.6, force: true)
        }
        syncAppearance(force: true)
    }

    private func endControl(restore: Bool) {
        timer?.invalidate()
        timer = nil
        lastApplied = nil
        lastBrightnessOffset = nil
        lastAppearanceDark = nil
        NightShift.setStatusHandler(nil)
        if restore, let snapshot {
            NightShift.restore(snapshot)
        }
        if restore, let appearanceSnapshot {
            MacAppearance.restore(appearanceSnapshot)
        }
        snapshot = nil
        appearanceSnapshot = nil
        persist()
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        currentWarmth = curve.warmth(at: Date())
        guard enabled, isSupported else { return }
        apply(period: 8, force: false)
        syncAppearance(force: false)
    }

    private func apply(period: TimeInterval, force: Bool, restyle: Bool = true) {
        currentWarmth = curve.warmth(at: Date())
        guard enabled, isSupported else { return }
        let warmth = currentWarmth
        let warmthMoved = force || lastApplied == nil || abs(lastApplied! - warmth) >= 0.008
        lastApplied = warmth
        guard warmthMoved else { return }
        let fade = period
        // Strength fades post many status notifications. Handling each one
        // with another apply() busy-waits CoreBrightness XPC on the main
        // actor and beachballs the app.
        ignoreSystemUntil = Date().addingTimeInterval(max(fade, 0.5) + 0.2)
        NightShift.apply(warmth: warmth, period: fade, restyle: restyle)
        applyExternalBrightness(force: force)
    }

    private func handleSystemNightShiftChanged() {
        guard enabled, isSupported, Date() >= ignoreSystemUntil else { return }
        apply(period: 0, force: true)
        syncAppearance(force: true)
    }

    private func applyAppearanceAfterEdit(scheduling: Bool) {
        guard enabled, isSupported else { return }
        if scheduling {
            lastAppearanceDark = nil
            syncAppearance(force: true)
        } else {
            let current = MacAppearance.snapshot()
            if var stored = appearanceSnapshot {
                stored.dark = current.dark
                appearanceSnapshot = stored
            } else {
                appearanceSnapshot = current
            }
            persist()
            MacAppearance.pin(appearanceSnapshot ?? current)
        }
    }

    private func syncAppearance(force: Bool) {
        if appearanceSchedule.enabled {
            applyScheduledAppearance(force: force)
            return
        }
        pinFrozenAppearance()
    }

    private func applyScheduledAppearance(force: Bool) {
        let solar = SolarTimes.today()
        let wantsDark = appearanceSchedule.wantsDark(at: Date(), solar: solar)
        if !force, lastAppearanceDark == wantsDark, MacAppearance.isCurrentlyDark() == wantsDark {
            return
        }
        MacAppearance.applyDark(wantsDark)
        lastAppearanceDark = wantsDark
    }

    private func pinFrozenAppearance() {
        if appearanceSnapshot?.automatic == true, lastAppearanceDark == nil {
            MacAppearance.restore(MacAppearance.Snapshot(automatic: true, dark: false))
            let current = MacAppearance.snapshot()
            if var stored = appearanceSnapshot {
                stored.dark = current.dark
                appearanceSnapshot = stored
            }
        }
        guard let appearanceSnapshot else { return }
        MacAppearance.pin(appearanceSnapshot)
        lastAppearanceDark = appearanceSnapshot.dark
    }

    private var brightnessOffset: Double {
        (0.5 - currentWarmth) * 2 * brightnessSwing
    }

    private func captureBaselines() {
        guard let displays = displayCatalog else { return }
        let offset = brightnessOffset
        for display in displays.displays where isExternalAdjustable(display) {
            brightnessBaselines[display.id] = min(max(display.brightness - offset, 0), 1)
        }
    }

    private func applyExternalBrightness(force: Bool) {
        guard enabled, isSupported, adjustExternalBrightness, let displays = displayCatalog else { return }
        let offset = brightnessOffset
        lastBrightnessOffset = offset
        var captured = false
        for display in displays.displays where isExternalAdjustable(display) {
            if brightnessBaselines[display.id] == nil {
                brightnessBaselines[display.id] = min(max(display.brightness - offset, 0), 1)
                captured = true
            }
            let base = brightnessBaselines[display.id] ?? display.brightness
            let target = min(max(base + offset, 0), 1)
            if force || abs(display.brightness - target) > 0.008 {
                displays.setBrightness(target, id: display.id, origin: .nightShift)
            }
        }
        if captured {
            persist()
        }
    }

    private func restoreExternalBrightness() {
        guard let displays = displayCatalog else { return }
        for (id, base) in brightnessBaselines {
            displays.setBrightness(base, id: id, origin: .nightShift)
        }
        lastBrightnessOffset = nil
    }

    private func isExternalAdjustable(_ display: AttachedDisplay) -> Bool {
        !display.isBuiltIn && display.canAdjustBrightness && !display.isDummy
    }

    private func observe() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        })
    }

    private func handleWake() {
        currentWarmth = curve.warmth(at: Date())
        guard enabled, isSupported else { return }
        NightShift.takeOverSchedule()
        apply(period: 1.2, force: true)
        syncAppearance(force: true)
    }

    private func persist() {
        let store = Store(
            enabled: enabled,
            curve: curve,
            snapshot: snapshot,
            appearanceSnapshot: appearanceSnapshot,
            adjustExternalBrightness: adjustExternalBrightness,
            brightnessSwing: brightnessSwing,
            brightnessBaselines: brightnessBaselines,
            appearanceSchedule: appearanceSchedule
        )
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let store = try? JSONDecoder().decode(Store.self, from: data) else { return }
        enabled = store.enabled
        snapshot = store.snapshot
        appearanceSnapshot = store.appearanceSnapshot
        adjustExternalBrightness = store.adjustExternalBrightness ?? false
        brightnessSwing = min(max(store.brightnessSwing ?? Self.defaultBrightnessSwing, 0), 0.5)
        brightnessBaselines = store.brightnessBaselines ?? [:]
        appearanceSchedule = store.appearanceSchedule ?? .factory
        if store.curve.matchesShape(of: .shippingV1) || store.curve.matchesShape(of: .shippingV2) {
            curve = .factory
            persist()
        } else {
            curve = store.curve
        }
    }

    private struct Store: Codable {
        var enabled: Bool
        var curve: NightShiftCurve
        var snapshot: NightShift.Snapshot?
        var appearanceSnapshot: MacAppearance.Snapshot?
        var adjustExternalBrightness: Bool?
        var brightnessSwing: Double?
        var brightnessBaselines: [String: Double]?
        var appearanceSchedule: AppearanceSchedule?
    }
}
