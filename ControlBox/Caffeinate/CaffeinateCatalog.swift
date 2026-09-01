import AppKit
import ControlBoxCore
import Foundation
import Observation

enum CaffeinateDuration: Int, CaseIterable, Identifiable, Hashable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case twentyMinutes = 1_200
    case thirtyMinutes = 1_800
    case fortyMinutes = 2_400
    case fiftyMinutes = 3_000
    case oneHour = 3_600
    case twoHours = 7_200
    case threeHours = 10_800
    case oneDay = 86_400
    case forever = 0

    var id: Int { rawValue }

    var seconds: TimeInterval? {
        self == .forever ? nil : TimeInterval(rawValue)
    }

    var title: String {
        switch self {
        case .oneMinute: return "1 Minute"
        case .fiveMinutes: return "5 Minutes"
        case .tenMinutes: return "10 Minutes"
        case .twentyMinutes: return "20 Minutes"
        case .thirtyMinutes: return "30 Minutes"
        case .fortyMinutes: return "40 Minutes"
        case .fiftyMinutes: return "50 Minutes"
        case .oneHour: return "1 Hour"
        case .twoHours: return "2 Hours"
        case .threeHours: return "3 Hours"
        case .oneDay: return "1 Day"
        case .forever: return "Forever"
        }
    }

    static func countdownText(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@Observable
@MainActor
final class CaffeinateCatalog {
    var isActive = false
    var duration: CaffeinateDuration?
    var endDate: Date?

    private let keepAwake = CaffeinateKeepAwake()
    private var expireTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    var remaining: TimeInterval? {
        guard isActive, let endDate else { return nil }
        return max(0, endDate.timeIntervalSinceNow)
    }

    var statusText: String {
        guard isActive else { return "Off" }
        if duration == .forever || endDate == nil {
            return "Staying awake"
        }
        if let remaining {
            return "Remaining \(CaffeinateDuration.countdownText(remaining: remaining))"
        }
        return "Staying awake"
    }

    init() {
        observe()
    }

    func start(_ duration: CaffeinateDuration) {
        keepAwake.stop()
        expireTimer?.invalidate()
        expireTimer = nil
        guard keepAwake.start() else {
            isActive = false
            self.duration = nil
            endDate = nil
            return
        }
        self.duration = duration
        if let seconds = duration.seconds {
            let end = Date().addingTimeInterval(seconds)
            endDate = end
            scheduleExpire(at: end)
        } else {
            endDate = nil
        }
        isActive = true
    }

    func stop() {
        expireTimer?.invalidate()
        expireTimer = nil
        keepAwake.stop()
        isActive = false
        duration = nil
        endDate = nil
    }

    func invalidate() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        stop()
    }

    private func scheduleExpire(at date: Date) {
        expireTimer?.invalidate()
        let interval = date.timeIntervalSinceNow
        if interval <= 0 {
            stop()
            return
        }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        expireTimer = timer
    }

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.expireIfNeeded()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleClockChange()
            }
        })
    }

    private func expireIfNeeded() {
        guard isActive, let endDate, Date() >= endDate else { return }
        stop()
    }

    private func handleClockChange() {
        guard isActive else { return }
        if let endDate {
            if Date() >= endDate {
                stop()
            } else {
                scheduleExpire(at: endDate)
            }
        }
    }
}
