import CoreFoundation
import Darwin
import Foundation
import IOKit.hid

/// Standalone DualSense Bluetooth mic capture. Not part of the app.
/// How to run, protocol, buzz, and quality: docs/dualsense-bluetooth-mic.md

private func log(_ line: String) {
    fputs(line + "\n", stderr)
    fflush(stderr)
}

private func hex(_ data: UnsafePointer<UInt8>, count: Int, limit: Int = 24) -> String {
    let n = min(count, limit)
    return (0..<n).map { String(format: "%02X", data[$0]) }.joined(separator: " ")
}

private func crc32IEEE(_ bytes: UnsafePointer<UInt8>, count: Int) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for i in 0..<count {
        crc ^= UInt32(bytes[i])
        for _ in 0..<8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ 0xEDB8_8320
            } else {
                crc >>= 1
            }
        }
    }
    return crc ^ 0xFFFF_FFFF
}

private func sealCRC(_ report: UnsafeMutablePointer<UInt8>, count: Int) {
    let split = count - 4
    var seeded = [UInt8](repeating: 0, count: split + 1)
    seeded[0] = 0xA2
    for i in 0..<split { seeded[i + 1] = report[i] }
    let crc = seeded.withUnsafeBufferPointer { crc32IEEE($0.baseAddress!, count: $0.count) }
    report[split] = UInt8(crc & 0xFF)
    report[split + 1] = UInt8((crc >> 8) & 0xFF)
    report[split + 2] = UInt8((crc >> 16) & 0xFF)
    report[split + 3] = UInt8((crc >> 24) & 0xFF)
}

private func krHex(_ kr: IOReturn) -> String {
    String(format: "0x%08X", UInt32(bitPattern: kr))
}

private let reportBytes = 78
private let maxStored = 20000

final class DualSenseMicCapture {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var hidBuffer: UnsafeMutablePointer<UInt8>?
    private let hidBufferSize = 256

    private var seq31: UInt8 = 0
    private var seqAudio: UInt8 = 0
    private var counter: UInt8 = 0
    private var enableTicks = 0
    private var dumped = 0
    private var keepAlive: Timer?

    private var stored: UnsafeMutablePointer<UInt8>
    private var storedCount: Int = 0
    private var totalReports: Int = 0

    private var silenceOpus = [UInt8]()
    private let seconds: TimeInterval
    private let wavPath: String

    private let stopOnly: Bool

    init(seconds: TimeInterval, wavPath: String, stopOnly: Bool = false) {
        self.seconds = seconds
        self.wavPath = wavPath
        self.stopOnly = stopOnly
        stored = .allocate(capacity: reportBytes * maxStored)
        stored.initialize(repeating: 0, count: reportBytes * maxStored)
    }

    deinit {
        stored.deallocate()
    }

    func run() {
        log("dualsense-mic: looking for Sony 054C:0CE6 / 0DF2")
        if !stopOnly {
            // mic-only capture does not need a speaker silence frame
        }
        openHID()
        guard device != nil else {
            log("no DualSense HID device — is the controller connected?")
            exit(1)
        }

        if stopOnly {
            DispatchQueue.main.async { [weak self] in
                self?.stopMotorsAndMic()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                CFRunLoopStop(CFRunLoopGetMain())
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.armMic()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.5) { [weak self] in
                self?.finish()
            }
        }
        CFRunLoopRun()
    }

    private func makeSilenceFrame() {
        var err: Int32 = 0
        guard let encoder = opus_encoder_create(48000, 2, OPUS_APPLICATION_AUDIO, &err),
              err == OPUS_OK
        else {
            log("opus_encoder_create failed \(err)")
            return
        }
        _ = ds_opus_set_bitrate(encoder, 160_000)
        _ = ds_opus_set_vbr(encoder, 0)
        _ = ds_opus_set_frame_10ms(encoder)
        let zeros = [Int16](repeating: 0, count: 960)
        var frame = [UInt8](repeating: 0, count: 200)
        let n = zeros.withUnsafeBufferPointer { pcmBuf in
            frame.withUnsafeMutableBufferPointer { out in
                opus_encode(encoder, pcmBuf.baseAddress!, 480, out.baseAddress!, 200)
            }
        }
        opus_encoder_destroy(encoder)
        if n > 0 {
            silenceOpus = Array(frame.prefix(Int(n)))
        }
        log("opus encoder ready, silence frame \(silenceOpus.count) B")
    }

    private func openHID() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDVendorIDKey as String: 0x054C, kIOHIDProductIDKey as String: 0x0CE6],
            [kIOHIDVendorIDKey as String: 0x054C, kIOHIDProductIDKey as String: 0x0DF2]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matching as CFArray)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openKR = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        log("manager open \(krHex(openKR))")
        manager = mgr

        guard let copied = IOHIDManagerCopyDevices(mgr) else {
            log("IOHIDManagerCopyDevices returned nil")
            return
        }
        var best: IOHIDDevice?
        var bestScore = -1
        for case let item as IOHIDDevice in (copied as NSSet) {
            let score = describe(item)
            if score > bestScore {
                bestScore = score
                best = item
            }
        }
        if let best {
            attach(best)
        }
    }

    @discardableResult
    private func describe(_ device: IOHIDDevice) -> Int {
        func num(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? -1
        }
        func str(_ key: String) -> String {
            (IOHIDDeviceGetProperty(device, key as CFString) as? String) ?? "?"
        }
        let product = str(kIOHIDProductKey)
        let transport = str(kIOHIDTransportKey)
        let page = num(kIOHIDPrimaryUsagePageKey)
        let usage = num(kIOHIDPrimaryUsageKey)
        let maxIn = num(kIOHIDMaxInputReportSizeKey)
        let maxOut = num(kIOHIDMaxOutputReportSizeKey)
        log(String(
            format: "  HID %@ transport=%@ page=%04X usage=%04X maxIn=%d maxOut=%d",
            product, transport, page, usage, maxIn, maxOut
        ))
        var score = 0
        if page == 0x01 && usage == 0x05 { score += 10 }
        if maxOut >= 142 { score += 20 }
        if maxIn >= 78 { score += 5 }
        return score
    }

    private func attach(_ device: IOHIDDevice) {
        let kr = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        log("device open \(krHex(kr))")
        self.device = device

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: hidBufferSize)
        buf.initialize(repeating: 0, count: hidBufferSize)
        hidBuffer = buf
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buf,
            hidBufferSize,
            { context, _, _, _, reportID, report, length in
                guard let context else { return }
                Unmanaged<DualSenseMicCapture>.fromOpaque(context).takeUnretainedValue()
                    .store(reportID: reportID, report: report, length: length)
            },
            pointer
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        log("listening for input reports")
    }

    private func store(reportID: UInt32, report: UnsafePointer<UInt8>, length: CFIndex) {
        totalReports += 1
        let count = Int(length)
        guard count > 0, storedCount < maxStored else { return }

        let dest = stored.advanced(by: storedCount * reportBytes)
        memset(dest, 0, reportBytes)
        if report[0] == 0x31 || report[0] == 0x01 {
            memcpy(dest, report, min(count, reportBytes))
        } else {
            dest[0] = UInt8(truncatingIfNeeded: reportID)
            memcpy(dest.advanced(by: 1), report, min(count, reportBytes - 1))
        }

        if dumped < 8 {
            let kind = ((dest[1] >> 1) & 1) == 1 ? "MIC" : "pad"
            log("RX \(kind) \(count)B b1=\(String(format: "%02X", dest[1]))  \(hex(dest, count: reportBytes))")
            dumped += 1
        }
        let micFlag = ((dest[1] >> 1) & 1) == 1
        guard micFlag else { return }
        storedCount += 1
    }

    private func armMic() {
        guard let device else { return }
        log("arming mic: unmute + mic-only 0x11, keep-alive 10 Hz")
        sendUnmute(device)
        sendEnable(device)
        var ticks = 0
        keepAlive?.invalidate()
        keepAlive = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
            guard let self, let device = self.device else {
                t.invalidate()
                return
            }
            self.sendEnable(device)
            ticks += 1
            if ticks >= 8 {
                t.invalidate()
                self.keepAlive = nil
            }
        }
    }

    private func sendUnmute(_ device: IOHIDDevice) {
        var report = [UInt8](repeating: 0, count: 78)
        report[0] = 0x31
        report[1] = (seq31 & 0x0F) << 4
        report[2] = 0x10
        report[3] = 0x40 | 0x80 // mic volume + audio control only — do not arm rumble/haptics
        report[4] = 0x01 | 0x02
        report[9] = 0x24
        report[11] = 0
        report[12] = 0
        report.withUnsafeMutableBufferPointer { buf in
            sealCRC(buf.baseAddress!, count: 78)
        }
        seq31 = (seq31 + 1) & 0x0F
        send(device, id: 0x31, bytes: report)
    }

    private func sendEnable(_ device: IOHIDDevice) {
        var report = [UInt8](repeating: 0, count: 142)
        report[0] = 0x32
        report[1] = (seqAudio & 0x0F) << 4
        report[2] = 0x11 | 0x80
        report[3] = 1
        report[4] = 0x03
        report.withUnsafeMutableBufferPointer { buf in
            sealCRC(buf.baseAddress!, count: 142)
        }
        seqAudio = (seqAudio + 1) & 0x0F
        send(device, id: 0x32, bytes: report)
    }

    private func send(_ device: IOHIDDevice, id: CFIndex, bytes: [UInt8]) {
        var withID = bytes
        let kr = withID.withUnsafeMutableBufferPointer { buf -> IOReturn in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, id, buf.baseAddress!, buf.count)
        }
        if enableTicks < 3 {
            log("TX report 0x\(String(id, radix: 16)) \(bytes.count)B \(krHex(kr))")
            enableTicks += 1
        }
    }

    private func finish() {
        let n = Int(storedCount)
        let total = Int(totalReports)
        keepAlive?.invalidate()
        keepAlive = nil
        log(String(
            format: "captured %d mic frames from %d HID reports (%.1f mic/s) — decoding",
            min(n, maxStored),
            total,
            Double(min(n, maxStored)) / max(seconds, 0.001)
        ))
        if let device {
            sendAudioMask(device, mask: 0x02)
        }
        decodeStored(count: min(n, maxStored))
        if let hidBuffer {
            hidBuffer.deallocate()
        }
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        CFRunLoopStop(CFRunLoopGetMain())
    }

    private func stopMotorsAndMic() {
        guard let device else { return }
        sendAudioMask(device, mask: 0x02)
        sendRumbleOff(device, hapticsSelect: true)
        sendRumbleOff(device, hapticsSelect: false)
        sendAudioMask(device, mask: 0x00)

        var ticks = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self, let device = self.device else {
                t.invalidate()
                return
            }
            self.sendRumbleOff(device, hapticsSelect: true)
            ticks += 1
            if ticks >= 24 {
                t.invalidate()
                self.sendAudioMask(device, mask: 0x00)
                self.sendRumbleOff(device, hapticsSelect: true)
                log("stopped rumble / haptics / mic")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sendAudioMask(_ device: IOHIDDevice, mask: UInt8) {
        var audio = [UInt8](repeating: 0, count: 142)
        audio[0] = 0x32
        audio[1] = (seqAudio & 0x0F) << 4
        audio[2] = 0x11 | 0x80
        audio[3] = 1
        audio[4] = mask
        audio.withUnsafeMutableBufferPointer { buf in
            sealCRC(buf.baseAddress!, count: 142)
        }
        seqAudio = (seqAudio + 1) & 0x0F
        send(device, id: 0x32, bytes: audio)
    }

    private func sendRumbleOff(_ device: IOHIDDevice, hapticsSelect: Bool) {
        var state = [UInt8](repeating: 0, count: 78)
        state[0] = 0x31
        state[1] = (seq31 & 0x0F) << 4
        state[2] = 0x10
        // rumble + optional HD haptics + both adaptive triggers + volumes + audio
        state[3] = 0x01 | (hapticsSelect ? 0x02 : 0) | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x80
        state[4] = 0x01 | 0x02 | 0x80
        state[11] = 1
        state[12] = 0x10
        state[41] = 0x04
        state.withUnsafeMutableBufferPointer { buf in
            sealCRC(buf.baseAddress!, count: 78)
        }
        send(device, id: 0x31, bytes: state)
    }

    private func decodeStored(count: Int) {
        var err: Int32 = 0
        guard let decoder = opus_decoder_create(48000, 1, &err), err == OPUS_OK else {
            log("opus_decoder_create failed \(err)")
            return
        }
        defer { opus_decoder_destroy(decoder) }

        let pcm = UnsafeMutablePointer<Int16>.allocate(capacity: 5760)
        defer { pcm.deallocate() }
        var wav = [Int16]()
        wav.reserveCapacity(count * 960)
        var mic = 0
        var decoded = 0
        var decodeErr = 0
        var concealed = 0
        var peak: Int16 = 0
        var lastSeq: Int?

        func appendFrame(_ got: Int32) {
            decoded += 1
            for s in 0..<Int(got) {
                let sample = pcm[s]
                wav.append(sample)
                let magnitude = sample == Int16.min ? Int16.max : abs(sample)
                if magnitude > peak { peak = magnitude }
            }
        }

        for i in 0..<count {
            let frame = stored.advanced(by: i * reportBytes)
            guard frame[0] == 0x31 else { continue }
            let micFlag = ((frame[1] >> 1) & 1) == 1
            guard micFlag else { continue }
            mic += 1
            let seq = Int(frame[1] >> 4)
            if let lastSeq {
                let missing = (seq - lastSeq - 1 + 16) % 16
                if missing > 0, missing <= 3 {
                    for _ in 0..<missing {
                        let got = opus_decode(decoder, nil, 0, pcm, 480, 0)
                        if got > 0 {
                            concealed += 1
                            appendFrame(got)
                        }
                    }
                }
            }
            lastSeq = seq
            let got = opus_decode(decoder, frame.advanced(by: 3), 71, pcm, 5760, 0)
            if got <= 0 {
                decodeErr += 1
                continue
            }
            appendFrame(got)
        }

        log(String(
            format: "decoded mic=%d plc=%d err=%d peak=%d raw=%.2fs",
            mic, concealed, decodeErr, peak, Double(wav.count) / 48000
        ))
        let cleaned = DualSenseMicCapture.polish(wav)
        writeWAV(cleaned)
    }

    private static func polish(_ samples: [Int16]) -> [Int16] {
        guard samples.count > 8 else { return samples }
        var prevX: Float = 0
        var prevY: Float = 0
        var filtered = [Float](repeating: 0, count: samples.count)
        var peak: Float = 0
        for i in 0..<samples.count {
            let x = Float(samples[i])
            let y = x - prevX + 0.997 * prevY
            prevX = x
            prevY = y
            filtered[i] = y
            peak = max(peak, abs(y))
        }
        guard peak > 8 else { return samples }
        let target: Float = 0.55 * 32767
        let gain = min(8, target / peak)
        log(String(format: "polish  dc-block  peak %.0f → gain %.2f", peak, gain))
        return filtered.map { sample in
            let v = sample * gain
            if v > 32767 { return Int16.max }
            if v < -32768 { return Int16.min }
            return Int16(v)
        }
    }

    private func writeWAV(_ samples: [Int16]) {
        guard !samples.isEmpty else {
            log("no PCM to write")
            return
        }
        var data = Data()
        func appendASCII(_ s: String) { data.append(contentsOf: s.utf8) }
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 4))
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        let dataBytes = UInt32(samples.count * 2)
        appendASCII("RIFF")
        appendU32(36 + dataBytes)
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(48000)
        appendU32(48000 * 2)
        appendU16(2)
        appendU16(16)
        appendASCII("data")
        appendU32(dataBytes)
        for sample in samples {
            var le = UInt16(bitPattern: sample).littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        do {
            try data.write(to: URL(fileURLWithPath: wavPath))
            log("wrote \(wavPath) (\(samples.count) samples, \(String(format: "%.2f", Double(samples.count) / 48000)) s)")
        } catch {
            log("wav write failed: \(error)")
        }
    }
}

private func hex(_ data: [UInt8], count: Int, limit: Int = 24) -> String {
    data.withUnsafeBufferPointer { hex($0.baseAddress!, count: count, limit: limit) }
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "stop" {
    log("stopping DualSense rumble / mic / haptics")
    DualSenseMicCapture(seconds: 0, wavPath: "", stopOnly: true).run()
} else {
    let seconds = args.first.flatMap(Double.init) ?? 8
    let wav = args.dropFirst().first ?? "/tmp/dualsense-mic.wav"
    log("capture \(seconds)s → \(wav)")
    log("speak into the controller mic")
    DualSenseMicCapture(seconds: seconds, wavPath: wav).run()
}
