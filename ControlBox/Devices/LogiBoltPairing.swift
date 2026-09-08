import Foundation
import Observation

/// Interactive Bolt pair: discover a list → user picks → passkey.
/// Mouse: 10 left/right clicks (MSB, RIGHT=1). Keyboard: typed ASCII digits.
@Observable
@MainActor
final class LogiBoltPairingSession {
    let receiverID: String
    let slot: Int
    var kind: LogiBoltPairKind = .mouse

    var phase: LogiBoltPairingPhase = .discovering
    var status: String
    var discovered: [LogiBoltDiscoveredDevice] = []
    var discoveredName = ""
    var discoveredWPID = 0
    var passkey = ""
    var mouseClicks: [LogiBoltClick] = []
    var enteredCount = 0
    var highlight: LogiBoltClick?
    var highlightBoth = false
    var expectedCount = 0

    var onFinished: (() -> Void)?
    var onNotificationsReleased: (() -> Void)?

    private let pipe: LogiBoltPipe
    private var generation = 0
    private var savedFlags: [UInt8]?
    private var address: [UInt8] = []
    private var advertisedAuth: UInt8 = 0
    private var discoveredKind = LogiBoltDeviceClass.unknown

    init(pipe: LogiBoltPipe, receiverID: String, slot: Int) {
        self.pipe = pipe
        self.receiverID = receiverID
        self.slot = slot
        status = LogiBoltPairKind.mouse.channelHint
    }

    var currentClick: LogiBoltClick? {
        guard enteredCount < mouseClicks.count else { return nil }
        return mouseClicks[enteredCount]
    }

    var passkeyCharacters: [Character] {
        Array(passkey)
    }

    func start() {
        generation += 1
        let gen = generation
        phase = .discovering
        kind = .mouse
        status = LogiBoltDiscovery.status
        discovered = []
        enteredCount = 0
        passkey = ""
        mouseClicks = []
        highlight = nil
        highlightBoth = false
        address = []
        discoveredName = ""
        pipe.onNotification = { [weak self] report in
            self?.handleNotification(report)
        }
        readFlagsThenDiscover(generation: gen)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(LogiBoltSupport.discoveryTimeoutSeconds)) { [weak self] in
            guard let self, self.generation == gen, self.phase == .discovering else { return }
            if self.discovered.isEmpty {
                self.status = "No devices advertised. Put a device in pairing mode and try again."
            } else {
                self.status = "Select a device to pair."
            }
        }
    }

    func select(_ device: LogiBoltDiscoveredDevice) {
        guard phase == .discovering else { return }
        address = device.address
        advertisedAuth = device.auth
        discoveredKind = device.deviceClass
        discoveredWPID = device.wpid
        discoveredName = device.displayName
        kind = device.deviceClass.isKeyboard ? .keyboard : .mouse
        phase = .connecting
        status = "Pairing \(device.displayName)…"
        let gen = generation
        stopDiscovery { [weak self] in
            guard let self, self.generation == gen else { return }
            self.sendPair(authTries: self.authSequence(), generation: gen)
        }
    }

    func cancel(silently: Bool = false) {
        generation += 1
        stopDiscovery { [weak self] in
            self?.restoreFlags()
            self?.releaseNotifications()
        }
        if !silently {
            phase = .cancelled
            status = "Cancelled."
            onFinished?()
        }
    }

    func fail(_ message: String) {
        generation += 1
        stopDiscovery { [weak self] in
            self?.restoreFlags()
            self?.releaseNotifications()
        }
        phase = .failed(message)
        status = message
        onFinished?()
    }

    func retry() {
        guard phase.isFinished || phase == .discovering else { return }
        start()
    }

    private func releaseNotifications() {
        pipe.onNotification = nil
        onNotificationsReleased?()
    }

    private func readFlagsThenDiscover(generation gen: Int) {
        pipe.getRegister(0x00) { [weak self] reply in
            guard let self, self.generation == gen else { return }
            if let bytes = reply.bytes, bytes.count > 6 {
                self.savedFlags = [bytes[4], bytes[5], bytes[6]]
                self.pipe.setRegister(0x00, p0: bytes[4], p1: bytes[5] | LogiBoltSupport.receiverNotificationFlags, p2: bytes[6]) { [weak self] _ in
                    guard let self, self.generation == gen else { return }
                    self.startDiscovery(generation: gen)
                }
            } else {
                self.startDiscovery(generation: gen)
            }
        }
    }

    private func startDiscovery(generation gen: Int) {
        pipe.setRegister(0xC0, p0: UInt8(LogiBoltSupport.discoveryTimeoutSeconds), p1: 0x01) { [weak self] reply in
            guard let self, self.generation == gen else { return }
            if case .error(let code) = reply {
                self.fail(String(format: "Discovery failed (error 0x%02X).", code))
                return
            }
            if case .timeout = reply {
                self.fail("Discovery timed out. Quit Logi Options+ if it is open.")
                return
            }
            self.status = LogiBoltDiscovery.status
        }
    }

    private func stopDiscovery(completion: @escaping () -> Void) {
        pipe.setRegister(0xC0, p0: 0, p1: 0x02) { _ in
            completion()
        }
    }

    private func restoreFlags() {
        guard let flags = savedFlags else { return }
        pipe.setRegister(0x00, p0: flags[0], p1: flags[1] | LogiBoltSupport.receiverNotificationFlags, p2: flags[2]) { _ in }
        savedFlags = nil
    }

    private func handleNotification(_ report: [UInt8]) {
        guard report.count > 3, report[1] == LogiBoltSupport.receiverIndex else {
            if Int(report[1]) == slot, LogiBoltSupport.isLinkEstablished(report) {
                succeed()
            }
            return
        }
        switch report[2] {
        case 0x4F:
            captureDiscovery(report)
        case 0x4D:
            capturePasskey(report)
        case 0x4E:
            captureKeypress(report)
        case 0x41:
            succeed()
        case 0x53:
            if phase == .discovering, report.count > 3, report[3] == 0x02 {
                if discovered.isEmpty {
                    status = "No devices advertised. Put a device in pairing mode and try again."
                } else {
                    status = "Select a device to pair."
                }
            }
        default:
            break
        }
    }

    private func captureDiscovery(_ report: [UInt8]) {
        guard phase == .discovering, report.count >= 20 else { return }
        let part = report[5]
        if part == 1 {
            applyDiscoveryName(report)
            return
        }
        guard part == 0 else { return }
        let address = Array(report[10..<16])
        let deviceClass = LogiBoltDeviceClass(raw: Int(report[16]))
        let wpid = Int(report[8]) | (Int(report[9]) << 8)
        let auth = report[7]
        if let index = discovered.firstIndex(where: { $0.address == address }) {
            discovered[index].wpid = wpid
            discovered[index].deviceClass = deviceClass
            discovered[index].auth = auth
            return
        }
        discovered.append(
            LogiBoltDiscoveredDevice(
                address: address,
                wpid: wpid,
                deviceClass: deviceClass,
                auth: auth,
                name: ""
            )
        )
        status = "Select a device to pair."
    }

    private func applyDiscoveryName(_ report: [UInt8]) {
        let name = Self.parseDiscoveryName(report)
        guard !name.isEmpty else { return }
        if report.count >= 16 {
            let address = Array(report[10..<16])
            if let index = discovered.firstIndex(where: { $0.address == address }) {
                discovered[index].name = name
                return
            }
        }
        if let last = discovered.indices.last {
            discovered[last].name = name
        }
    }

    private static func parseDiscoveryName(_ report: [UInt8]) -> String {
        guard report.count > 7 else { return "" }
        let length = min(Int(report[6]), max(report.count - 7, 0))
        if length > 0 {
            let parsed = LogiBoltSupport.ascii(report[7..<(7 + length)]).trimmingCharacters(in: .whitespaces)
            if !parsed.isEmpty { return parsed }
        }
        return LogiBoltSupport.ascii(report[6..<report.count]).trimmingCharacters(in: .whitespaces)
    }

    private func authSequence() -> [UInt8] {
        var values: [UInt8] = []
        for candidate in [advertisedAuth, 0x02, 0x01, 0x10, 0x00] {
            if !values.contains(candidate) {
                values.append(candidate)
            }
        }
        return values
    }

    private func sendPair(authTries: [UInt8], generation gen: Int) {
        guard let auth = authTries.first else {
            fail("The receiver rejected pairing.")
            return
        }
        var payload = [UInt8](repeating: 0, count: 16)
        payload[0] = 0x01
        payload[1] = UInt8(slot)
        for (offset, byte) in address.prefix(6).enumerated() {
            payload[2 + offset] = byte
        }
        payload[8] = auth
        payload[9] = kind.entropy
        pipe.setLongRegister(0xC1, payload: payload) { [weak self] reply in
            guard let self, self.generation == gen else { return }
            if case .error = reply {
                self.sendPair(authTries: Array(authTries.dropFirst()), generation: gen)
                return
            }
            if case .timeout = reply {
                self.fail("Pairing timed out. Quit Logi Options+ if it is open.")
                return
            }
            self.status = "Waiting for the passkey…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, self.generation == gen, self.passkey.isEmpty, self.phase == .connecting else { return }
                if authTries.count > 1 {
                    self.sendPair(authTries: Array(authTries.dropFirst()), generation: gen)
                } else {
                    self.fail("No passkey arrived. Put the device in pairing mode and try again.")
                }
            }
        }
    }

    private func capturePasskey(_ report: [UInt8]) {
        guard phase == .connecting || phase == .enterPasskey, report.count > 4, passkey.isEmpty else { return }
        let count = Int(report[3])
        var digits = ""
        for offset in 0..<count where 4 + offset < report.count {
            let byte = report[4 + offset]
            guard byte >= 48, byte <= 57, let scalar = UnicodeScalar(UInt32(byte)) else { continue }
            digits.append(Character(scalar))
        }
        guard !digits.isEmpty else { return }
        passkey = digits
        if kind == .keyboard {
            expectedCount = digits.count
            status = "Type this code on the keyboard, then press Return."
        } else {
            let value = Int(digits) ?? 0
            let bits = Int(kind.entropy)
            mouseClicks = Self.clickSequence(passkey: value, bits: bits)
            expectedCount = bits
            highlight = mouseClicks.first
            status = "Click this sequence, then Left and Right together."
        }
        phase = .enterPasskey
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(LogiBoltSupport.passkeyTimeoutSeconds)) { [weak self] in
            guard let self, self.generation == gen, self.phase == .enterPasskey else { return }
            self.fail("Passkey entry timed out.")
        }
    }

    private func captureKeypress(_ report: [UInt8]) {
        guard phase == .enterPasskey, report.count > 3 else { return }
        guard let press = LogiBoltKeypress(code: report[3]) else { return }
        switch press {
        case .started:
            enteredCount = 0
            highlight = currentClick
            highlightBoth = false
        case .registered:
            enteredCount = min(enteredCount + 1, max(expectedCount, 1))
            if kind == .mouse {
                if enteredCount >= mouseClicks.count {
                    highlight = nil
                    highlightBoth = true
                    status = "Now click Left and Right together to confirm."
                } else {
                    highlight = currentClick
                    highlightBoth = false
                }
            }
        case .erased:
            enteredCount = max(enteredCount - 1, 0)
            highlightBoth = false
            highlight = currentClick
        case .cleared:
            enteredCount = 0
            highlightBoth = false
            highlight = currentClick
        case .completed:
            succeed()
        }
    }

    private func succeed() {
        guard !phase.isFinished else { return }
        generation += 1
        restoreFlags()
        releaseNotifications()
        phase = .succeeded
        highlightBoth = false
        highlight = nil
        enteredCount = max(enteredCount, expectedCount)
        status = "\(discoveredName.isEmpty ? kind.title : discoveredName) is paired on slot \(slot)."
        onFinished?()
    }

    /// Verified on MX Master 4: MSB first, RIGHT = 1, LEFT = 0.
    static func clickSequence(passkey: Int, bits: Int) -> [LogiBoltClick] {
        (0..<bits).map { index in
            let bit = (passkey >> (bits - 1 - index)) & 1
            return bit == 1 ? .right : .left
        }
    }
}
