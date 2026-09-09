import Foundation
import IOKit.hid
import Observation

/// Owns every plugged Logi Bolt receiver’s vendor HID++ pipe. Pair / unpair
/// and slot HID++ talk. Do not open the mouse or keyboard collections.
@Observable
@MainActor
final class LogiBoltCatalog {
    var receivers: [LogiBoltReceiverSnapshot] = []
    var pairing: LogiBoltPairingSession?
    var isWatching = false
    var keepAlive = false
    var onReceiversChanged: (() -> Void)?

    var isTalkSuspended: Bool {
        if let pairing, !pairing.phase.isFinished { return true }
        return false
    }

    private var manager: IOHIDManager?
    private var pipes: [String: LogiBoltPipe] = [:]
    private var sheetVisible = false
    private var refreshGeneration: [String: Int] = [:]
    private var liveOnline: [String: Set<Int>] = [:]
    private var flagsReady: Set<String> = []
    private var stopWatchingWork: DispatchWorkItem?
    private var talkLinks: [String: LogiBoltHIDPPLink] = [:]
    private var notifyWork: DispatchWorkItem?

    func sheetAppeared() {
        stopWatchingWork?.cancel()
        stopWatchingWork = nil
        sheetVisible = true
        startWatching()
    }

    func sheetDisappeared() {
        sheetVisible = false
        scheduleStopIfIdle()
    }

    func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, LogiBoltSupport.hidManagerMatch() as CFDictionary)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, device in
            guard let context else { return }
            let catalog = Unmanaged<LogiBoltCatalog>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                catalog.attach(device)
            }
        }, pointer)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, device in
            guard let context else { return }
            let catalog = Unmanaged<LogiBoltCatalog>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                catalog.detach(device)
            }
        }, pointer)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
        scan()
    }

    func stopWatching() {
        pairing?.cancel(silently: true)
        pairing = nil
        stopWatchingWork?.cancel()
        stopWatchingWork = nil
        notifyWork?.cancel()
        notifyWork = nil
        releaseTalkLinks()
        for pipe in pipes.values {
            pipe.onNotification = nil
            pipe.onRemoved = nil
            pipe.close()
        }
        pipes.removeAll()
        refreshGeneration.removeAll()
        flagsReady.removeAll()
        liveOnline.removeAll()
        receivers.removeAll()
        notifyReceiversChanged()
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        isWatching = false
    }

    func refresh() {
        for pipe in pipes.values {
            refresh(pipe, attemptsLeft: 4)
        }
    }

    func unpair(receiverID: String, slot: Int, completion: @escaping (String?) -> Void) {
        guard pairing == nil else {
            completion("Finish pairing first.")
            return
        }
        guard let pipe = pipes[receiverID] else {
            completion("Receiver is gone.")
            return
        }
        var payload = [UInt8](repeating: 0, count: 16)
        payload[0] = 0x03
        payload[1] = UInt8(slot)
        pipe.setLongRegister(0xC1, payload: payload) { [weak self] reply in
            guard let self else { return }
            switch reply {
            case .ok:
                self.liveOnline[receiverID]?.remove(slot)
                if let link = self.talkLinks["\(receiverID)-\(slot)"] {
                    self.releaseTalkLink(link)
                }
                self.refresh(pipe)
                self.notifyReceiversChanged()
                completion(nil)
            case .error(let code):
                completion(String(format: "Unpair failed (error 0x%02X).", code))
            case .timeout:
                completion("Unpair timed out. Quit Logi Options+ if it is open.")
            }
        }
    }

    func beginPairing(receiverID: String) -> String? {
        guard pairing == nil || pairing?.phase.isFinished == true else {
            return "A pairing is already in progress."
        }
        startWatching()
        guard let pipe = pipes[receiverID] else {
            return "Plug in a Logi Bolt receiver."
        }
        guard let snapshot = receivers.first(where: { $0.id == receiverID }) else {
            return "Receiver is still loading."
        }
        guard let slot = snapshot.emptySlot else {
            return "This receiver is full (\(snapshot.slotCount) devices)."
        }
        bumpGeneration(pipe)
        releaseTalkLinks(receiverID: receiverID)
        notifyReceiversChanged()
        let session = LogiBoltPairingSession(pipe: pipe, receiverID: receiverID, slot: slot)
        session.onFinished = { [weak self] in
            self?.pairingDidFinish()
        }
        session.onNotificationsReleased = { [weak self] in
            self?.listenForConnections(on: pipe)
        }
        pairing = session
        session.start()
        return nil
    }

    func cancelPairing() {
        pairing?.cancel()
    }

    func pairingWindowClosed() {
        if let session = pairing, !session.phase.isFinished {
            session.cancel()
        }
        pairing = nil
        notifyReceiversChanged()
        scheduleStopIfIdle()
    }

    private func scheduleStopIfIdle() {
        stopWatchingWork?.cancel()
        guard !keepAlive, !sheetVisible, pairing == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.keepAlive, !self.sheetVisible, self.pairing == nil else { return }
            self.stopWatching()
        }
        stopWatchingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func talkLink(receiverID: String, slot: Int) -> LogiBoltHIDPPLink? {
        guard !isTalkSuspended else { return nil }
        let key = "\(receiverID)-\(slot)"
        if let existing = talkLinks[key] { return existing }
        guard let pipe = pipes[receiverID] else { return nil }
        let link = LogiBoltHIDPPLink(pipe: pipe, slot: slot)
        talkLinks[key] = link
        return link
    }

    func releaseTalkLink(_ link: LogiBoltHIDPPLink) {
        let key = link.id
        guard talkLinks[key] === link else { return }
        link.detach()
        talkLinks.removeValue(forKey: key)
    }

    func releaseTalkLinks(receiverID: String? = nil) {
        let keys = talkLinks.keys.filter { key in
            guard let receiverID else { return true }
            return key.hasPrefix("\(receiverID)-")
        }
        for key in keys {
            talkLinks[key]?.detach()
            talkLinks.removeValue(forKey: key)
        }
    }

    private func bumpGeneration(_ pipe: LogiBoltPipe) -> Int {
        let next = (refreshGeneration[pipe.id] ?? 0) + 1
        refreshGeneration[pipe.id] = next
        return next
    }

    private func generationMatches(_ pipe: LogiBoltPipe, _ generation: Int) -> Bool {
        refreshGeneration[pipe.id] == generation
    }

    private func pairingDidFinish() {
        guard let receiverID = pairing?.receiverID else { return }
        let succeeded = pairing?.phase == .succeeded
        guard let pipe = pipes[receiverID] else { return }
        listenForConnections(on: pipe)
        refresh(pipe, attemptsLeft: succeeded ? 8 : 1)
        notifyReceiversChanged()
    }

    private func scan() {
        guard let manager, let copied = IOHIDManagerCopyDevices(manager) else { return }
        for case let device as IOHIDDevice in (copied as NSSet) {
            attach(device)
        }
        publishEmptyIfNeeded()
    }

    private func attach(_ device: IOHIDDevice) {
        guard isWatching, LogiBoltSupport.isVendorHIDPP(device) else { return }
        if pipes.values.contains(where: { $0.isSameDevice(device) }) { return }
        let id = LogiBoltSupport.identity(of: device)
        if pipes[id] != nil { return }
        if let serial = LogiBoltSupport.stringProperty(kIOHIDSerialNumberKey as String, device), !serial.isEmpty,
           pipes.values.contains(where: { $0.serial == serial }) {
            return
        }
        guard let pipe = LogiBoltPipe(device: device) else { return }
        guard pipe.open() else { return }
        pipes[pipe.id] = pipe
        pipe.onRemoved = { [weak self, id = pipe.id] in
            self?.removePipe(id)
        }
        listenForConnections(on: pipe)
        insertPlaceholder(pipe)
        refresh(pipe)
    }

    private func detach(_ device: IOHIDDevice) {
        guard let pipe = pipes.values.first(where: { $0.isSameDevice(device) }) else { return }
        if pairing?.receiverID == pipe.id {
            pairing?.fail("The Bolt receiver was unplugged.")
        }
        removePipe(pipe.id)
    }

    private func removePipe(_ id: String) {
        releaseTalkLinks(receiverID: id)
        if let pipe = pipes.removeValue(forKey: id) {
            pipe.onNotification = nil
            pipe.close()
        }
        liveOnline.removeValue(forKey: id)
        flagsReady.remove(id)
        refreshGeneration.removeValue(forKey: id)
        receivers.removeAll { $0.id == id }
        publishEmptyIfNeeded()
        notifyReceiversChanged()
    }

    private func insertPlaceholder(_ pipe: LogiBoltPipe) {
        if receivers.contains(where: { $0.id == pipe.id }) { return }
        if !pipe.serial.isEmpty, receivers.contains(where: { $0.serial == pipe.serial }) { return }
        receivers.append(
            LogiBoltReceiverSnapshot(
                id: pipe.id,
                serial: pipe.serial,
                productName: pipe.productName,
                title: pipe.productName,
                slotCount: 5,
                pairedCount: 0,
                devices: [],
                status: "Reading paired devices…",
                isLoading: true
            )
        )
        retitleReceivers()
    }

    private func refresh(_ pipe: LogiBoltPipe, attemptsLeft: Int = 1) {
        let gen = bumpGeneration(pipe)
        let start = { [weak self] in
            guard let self, self.generationMatches(pipe, gen) else { return }
            self.readReceiverInfo(pipe, generation: gen, attemptsLeft: attemptsLeft)
        }
        if flagsReady.contains(pipe.id) {
            start()
            return
        }
        enableReceiverNotifications(pipe, generation: gen, then: start)
    }

    private func readReceiverInfo(_ pipe: LogiBoltPipe, generation: Int, attemptsLeft: Int) {
        pipe.getLongRegister(0xB5, sub: 0x02) { [weak self] info in
            guard let self, self.generationMatches(pipe, generation) else { return }
            let slots: Int
            if let bytes = info.bytes, bytes.count > 5 {
                slots = max(1, min(LogiBoltSupport.maxSlots, Int(bytes[5])))
            } else {
                slots = 5
            }
            pipe.getRegister(0x02) { [weak self] state in
                guard let self, self.generationMatches(pipe, generation) else { return }
                let paired: Int
                if let bytes = state.bytes, bytes.count > 5 {
                    paired = Int(bytes[5])
                } else {
                    paired = self.receivers.first(where: { $0.id == pipe.id })?.devices.count ?? 0
                }
                self.publishWalk(
                    pipe: pipe,
                    found: [],
                    remaining: Array(1...slots),
                    slots: slots,
                    paired: paired,
                    loading: self.receivers.first(where: { $0.id == pipe.id })?.devices.isEmpty ?? true
                )
                self.readSlots(
                    pipe: pipe,
                    remaining: Array(1...slots),
                    devices: [],
                    slots: slots,
                    paired: paired,
                    generation: generation,
                    attemptsLeft: attemptsLeft
                )
            }
        }
    }

    private func readSlots(
        pipe: LogiBoltPipe,
        remaining: [Int],
        devices: [LogiBoltPairedDevice],
        slots: Int,
        paired: Int,
        generation: Int,
        attemptsLeft: Int
    ) {
        guard generationMatches(pipe, generation) else { return }
        guard let slot = remaining.first else {
            publishWalk(
                pipe: pipe,
                found: devices,
                remaining: [],
                slots: slots,
                paired: max(paired, devices.count),
                loading: false
            )
            if devices.count < paired, attemptsLeft > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    guard let self, let current = self.pipes[pipe.id], self.generationMatches(pipe, generation) else { return }
                    self.refresh(current, attemptsLeft: attemptsLeft - 1)
                }
            } else {
                probeConnections(pipe, generation: generation)
            }
            return
        }
        readSlotRecord(
            pipe: pipe,
            slot: slot,
            remaining: remaining,
            devices: devices,
            slots: slots,
            paired: paired,
            generation: generation,
            attemptsLeft: attemptsLeft,
            recordTries: 3
        )
    }

    private func readSlotRecord(
        pipe: LogiBoltPipe,
        slot: Int,
        remaining: [Int],
        devices: [LogiBoltPairedDevice],
        slots: Int,
        paired: Int,
        generation: Int,
        attemptsLeft: Int,
        recordTries: Int
    ) {
        pipe.getLongRegister(0xB5, sub: UInt8(0x50 + slot)) { [weak self] record in
            guard let self, self.generationMatches(pipe, generation) else { return }
            let skip = {
                self.readSlots(
                    pipe: pipe,
                    remaining: Array(remaining.dropFirst()),
                    devices: devices,
                    slots: slots,
                    paired: paired,
                    generation: generation,
                    attemptsLeft: attemptsLeft
                )
            }
            switch record {
            case .timeout:
                if recordTries > 1 {
                    self.readSlotRecord(
                        pipe: pipe,
                        slot: slot,
                        remaining: remaining,
                        devices: devices,
                        slots: slots,
                        paired: paired,
                        generation: generation,
                        attemptsLeft: attemptsLeft,
                        recordTries: recordTries - 1
                    )
                } else {
                    skip()
                }
            case .error:
                if recordTries > 2 {
                    self.readSlotRecord(
                        pipe: pipe,
                        slot: slot,
                        remaining: remaining,
                        devices: devices,
                        slots: slots,
                        paired: paired,
                        generation: generation,
                        attemptsLeft: attemptsLeft,
                        recordTries: recordTries - 1
                    )
                } else {
                    skip()
                }
            case .ok(let bytes):
                guard bytes.count > 15 else {
                    skip()
                    return
                }
                let flags = bytes[5]
                let wpid = Int(bytes[6]) | (Int(bytes[7]) << 8)
                if flags == 0 && wpid == 0 {
                    skip()
                    return
                }
                let unit = (UInt32(bytes[8]) << 24) | (UInt32(bytes[9]) << 16) | (UInt32(bytes[10]) << 8) | UInt32(bytes[11])
                let deviceClass = LogiBoltDeviceClass(raw: Int(bytes[14]))
                let entropy = Int(bytes[15])
                let kind = LogiBoltSupport.classify(wpid: wpid, name: "", deviceClass: deviceClass)
                var next = devices
                next.append(
                    LogiBoltPairedDevice(
                        receiverID: pipe.id,
                        slot: slot,
                        deviceClass: deviceClass,
                        wpid: wpid,
                        unitID: unit,
                        name: "",
                        entropyBits: entropy,
                        online: false,
                        status: "Not connected",
                        deviceKind: kind
                    )
                )
                self.publishWalk(
                    pipe: pipe,
                    found: next,
                    remaining: Array(remaining.dropFirst()),
                    slots: slots,
                    paired: max(paired, next.count),
                    loading: false
                )
                self.readName(pipe: pipe, slot: slot) { name in
                    guard self.generationMatches(pipe, generation) else { return }
                    if !name.isEmpty, let index = next.firstIndex(where: { $0.slot == slot }) {
                        next[index].name = name
                        next[index].deviceKind = LogiBoltSupport.classify(
                            wpid: wpid,
                            name: name,
                            deviceClass: deviceClass
                        )
                        self.publishWalk(
                            pipe: pipe,
                            found: next,
                            remaining: Array(remaining.dropFirst()),
                            slots: slots,
                            paired: max(paired, next.count),
                            loading: false
                        )
                    }
                    self.readSlots(
                        pipe: pipe,
                        remaining: Array(remaining.dropFirst()),
                        devices: next,
                        slots: slots,
                        paired: paired,
                        generation: generation,
                        attemptsLeft: attemptsLeft
                    )
                }
            }
        }
    }

    private func publishWalk(
        pipe: LogiBoltPipe,
        found: [LogiBoltPairedDevice],
        remaining: [Int],
        slots: Int,
        paired: Int,
        loading: Bool
    ) {
        let existing = receivers.first(where: { $0.id == pipe.id })?.devices ?? []
        let foundSlots = Set(found.map(\.slot))
        let pendingSlots = Set(remaining)
        var merged = found
        for device in existing where !foundSlots.contains(device.slot) && pendingSlots.contains(device.slot) {
            merged.append(device)
        }
        apply(
            pipe: pipe,
            slots: slots,
            paired: max(paired, merged.count),
            devices: merged,
            status: loading ? "Reading paired devices…" : nil,
            loading: loading && merged.isEmpty
        )
    }

    private func readName(pipe: LogiBoltPipe, slot: Int, completion: @escaping (String) -> Void) {
        pipe.getLongRegister(0xB5, sub: UInt8(0x60 + slot), p1: 0x01) { reply in
            guard let bytes = reply.bytes, bytes.count > 7 else {
                completion("")
                return
            }
            let length = min(Int(bytes[6]), max(bytes.count - 7, 0))
            let name = LogiBoltSupport.ascii(bytes[7..<(7 + length)])
            completion(name.trimmingCharacters(in: .whitespaces))
        }
    }

    private func listenForConnections(on pipe: LogiBoltPipe) {
        guard pairing?.receiverID != pipe.id || pairing?.phase.isFinished == true else { return }
        pipe.onNotification = { [weak self] report in
            self?.handleConnectionNotification(receiverID: pipe.id, report)
        }
    }

    private func enableReceiverNotifications(_ pipe: LogiBoltPipe, generation: Int, then completion: @escaping () -> Void) {
        pipe.getRegister(0x00) { [weak self] flags in
            guard let self, self.generationMatches(pipe, generation) else { return }
            if let bytes = flags.bytes, bytes.count > 6 {
                pipe.setRegister(
                    0x00,
                    p0: bytes[4],
                    p1: bytes[5] | LogiBoltSupport.receiverNotificationFlags,
                    p2: bytes[6]
                ) { [weak self] _ in
                    self?.flagsReady.insert(pipe.id)
                    completion()
                }
            } else {
                completion()
            }
        }
    }

    private func handleConnectionNotification(receiverID: String, _ report: [UInt8]) {
        if let slot = LogiBoltSupport.connectionSlot(from: report) {
            switch report[2] {
            case 0x41:
                setOnline(receiverID: receiverID, slot: slot, online: LogiBoltSupport.isLinkEstablished(report))
            case 0x40:
                setOnline(receiverID: receiverID, slot: slot, online: false)
            default:
                break
            }
            return
        }
        guard report.count > 1 else { return }
        let slot = Int(report[1])
        guard slot >= 1, slot <= LogiBoltSupport.maxSlots else { return }
        talkLinks["\(receiverID)-\(slot)"]?.onReport?(report)
    }

    private func setOnline(receiverID: String, slot: Int, online: Bool) {
        if online {
            liveOnline[receiverID, default: []].insert(slot)
        } else {
            liveOnline[receiverID, default: []].remove(slot)
        }
        guard let receiverIndex = receivers.firstIndex(where: { $0.id == receiverID }) else { return }
        guard let deviceIndex = receivers[receiverIndex].devices.firstIndex(where: { $0.slot == slot }) else { return }
        receivers[receiverIndex].devices[deviceIndex].online = online
        receivers[receiverIndex].devices[deviceIndex].status = online ? "Online" : "Not connected"
        notifyReceiversChanged()
    }

    private func probeConnections(_ pipe: LogiBoltPipe, generation: Int) {
        guard pairing == nil || pairing?.phase.isFinished == true else { return }
        listenForConnections(on: pipe)
        pipe.setRegister(0x02, p0: 0x02) { [weak self] _ in
            guard let self, self.generationMatches(pipe, generation) else { return }
            self.pingSlots(
                pipe,
                remaining: self.receivers.first(where: { $0.id == pipe.id })?.devices.map(\.slot) ?? [],
                generation: generation
            )
        }
    }

    private func pingSlots(_ pipe: LogiBoltPipe, remaining: [Int], generation: Int) {
        guard pairing == nil || pairing?.phase.isFinished == true else { return }
        guard generationMatches(pipe, generation) else { return }
        guard let slot = remaining.first else {
            notifyReceiversChanged()
            return
        }
        if talkLinks["\(pipe.id)-\(slot)"] != nil {
            pingSlots(pipe, remaining: Array(remaining.dropFirst()), generation: generation)
            return
        }
        pipe.ping(slot: slot) { [weak self] reply in
            guard let self, self.generationMatches(pipe, generation) else { return }
            switch reply {
            case .ok, .error:
                self.setOnline(receiverID: pipe.id, slot: slot, online: true)
            case .timeout:
                break
            }
            self.pingSlots(pipe, remaining: Array(remaining.dropFirst()), generation: generation)
        }
    }

    private func apply(
        pipe: LogiBoltPipe,
        slots: Int,
        paired: Int,
        devices: [LogiBoltPairedDevice],
        status: String?,
        loading: Bool
    ) {
        let onlineSlots = liveOnline[pipe.id] ?? []
        var listed = devices.sorted { $0.slot < $1.slot }
        for index in listed.indices {
            let on = onlineSlots.contains(listed[index].slot)
            listed[index].online = on
            listed[index].status = on ? "Online" : "Not connected"
        }
        let snapshot = LogiBoltReceiverSnapshot(
            id: pipe.id,
            serial: pipe.serial,
            productName: pipe.productName,
            title: pipe.productName,
            slotCount: slots,
            pairedCount: paired,
            devices: listed,
            status: status,
            isLoading: loading
        )
        if let index = receivers.firstIndex(where: { $0.id == pipe.id }) {
            receivers[index] = snapshot
        } else {
            receivers.append(snapshot)
        }
        retitleReceivers()
        if !loading {
            notifyReceiversChanged()
        }
    }

    private func notifyReceiversChanged() {
        notifyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onReceiversChanged?()
        }
        notifyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func retitleReceivers() {
        let total = receivers.count
        for index in receivers.indices {
            receivers[index].title = LogiBoltSupport.displayName(
                serial: receivers[index].serial,
                product: receivers[index].productName,
                index: index + 1,
                total: total
            )
        }
    }

    private func publishEmptyIfNeeded() {
        if pipes.isEmpty {
            receivers = []
        }
    }
}
