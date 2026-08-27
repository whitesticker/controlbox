import AppKit
import ControlBoxCore
import Foundation
import Observation

@Observable
@MainActor
final class NightShiftCatalog {
    var enabled = false
    var curve = NightShiftCurve.factory
    var isSupported = false
    var range = NightShift.CCTRange.fallback
    var currentWarmth = 0.0

    private var snapshot: NightShift.Snapshot?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastApplied: Double?
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

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        guard !on || isSupported else { return }
        enabled = on
        persist()
        if on {
            beginControl(applyImmediately: true)
        } else {
            endControl(restore: true)
        }
    }

    func resetCurve() {
        curve = .factory
        persist()
        apply(period: 1.2, force: true)
    }

    func movePoint(id: String, minutes: Double, warmth: Double, live: Bool) {
        curve.move(id: id, minutes: minutes, warmth: warmth)
        currentWarmth = curve.warmth(at: Date())
        apply(period: live ? 0.18 : 1.4, force: !live)
        if !live {
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
    }

    private func beginControl(applyImmediately: Bool) {
        if snapshot == nil {
            snapshot = NightShift.snapshot()
            persist()
        }
        NightShift.takeOverSchedule()
        startTimer()
        if applyImmediately {
            apply(period: 1.6, force: true)
        }
    }

    private func endControl(restore: Bool) {
        timer?.invalidate()
        timer = nil
        lastApplied = nil
        if restore, let snapshot {
            NightShift.restore(snapshot)
        }
        snapshot = nil
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
    }

    private func apply(period: TimeInterval, force: Bool) {
        currentWarmth = curve.warmth(at: Date())
        guard enabled, isSupported else { return }
        let warmth = currentWarmth
        if !force, let lastApplied, abs(lastApplied - warmth) < 0.008 {
            return
        }
        lastApplied = warmth
        NightShift.apply(warmth: warmth, period: period)
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
    }

    private func persist() {
        let store = Store(enabled: enabled, curve: curve, snapshot: snapshot)
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let store = try? JSONDecoder().decode(Store.self, from: data) else { return }
        enabled = store.enabled
        snapshot = store.snapshot
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
    }
}
