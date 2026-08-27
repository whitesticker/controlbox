import AppKit
import AudioToolbox
import AudioUnit
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import os

/// One app that is playing (or has a remembered volume). Mixer uses Apple process taps only.
public struct AttachedAudioApp: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var volume: Double
    public var isMuted: Bool
    public var isPlaying: Bool
    public var canAdjust: Bool

    public init(
        id: String,
        name: String,
        volume: Double,
        isMuted: Bool,
        isPlaying: Bool,
        canAdjust: Bool
    ) {
        self.id = id
        self.name = name
        self.volume = volume
        self.isMuted = isMuted
        self.isPlaying = isPlaying
        self.canAdjust = canAdjust
    }
}

public enum AppVolumeMixer {
    public static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    /// Per-app volume needs System Audio Recording (`kTCCServiceAudioCapture`).
    /// Screen Recording is a different grant; on macOS 26 it also covers taps,
    /// but an audio-only grant does not set `CGPreflightScreenCaptureAccess()`.
    public static var hasCaptureAccess: Bool {
        if AudioCaptureTCC.preflight() == .authorized { return true }
        if CGPreflightScreenCaptureAccess() { return true }
        tapAccessLock.lock()
        let tapped = observedTapAuthorized
        tapAccessLock.unlock()
        return tapped
    }

    public static func requestCaptureAccess(completion: ((Bool) -> Void)? = nil) {
        AudioCaptureTCC.request { granted in
            completion?(granted || hasCaptureAccess)
        }
    }

    public static func openCaptureSettings() {
        let prefixes = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?",
            "x-apple.systempreferences:com.apple.preference.security?"
        ]
        for prefix in prefixes {
            if let url = URL(string: prefix + "Privacy_ScreenCapture"),
               NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    public static func apps() -> [AttachedAudioApp] {
        if #available(macOS 14.2, *) {
            return Engine.shared.snapshot()
        }
        return []
    }

    public static func setVolume(_ value: Double, id: String) {
        if #available(macOS 14.2, *) {
            Engine.shared.setVolume(value, id: id)
        }
    }

    public static func setMuted(_ muted: Bool, id: String) {
        if #available(macOS 14.2, *) {
            Engine.shared.setMuted(muted, id: id)
        }
    }

    public static func lastError() -> String? {
        if #available(macOS 14.2, *) {
            return Engine.shared.lastError
        }
        return "Per-app volume needs macOS 14.2 or later."
    }

    /// Other process-tap mixers already mute-when-tapped; a second tap is silent or no-ops.
    public static func conflictingMixerNames() -> [String] {
        let known: [(bundle: String, name: String)] = [
            ("com.finetuneapp.FineTune", "FineTune"),
            ("com.rogueamoeba.soundsource", "SoundSource"),
            ("com.rogueamoeba.audiohijack", "Audio Hijack"),
            ("com.rogueamoeba.loopback", "Loopback"),
            ("com.kyleneideck.BackgroundMusic", "Background Music"),
            ("com.bearisdriving.BGMApp", "Background Music")
        ]
        let running = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        return known.compactMap { running.contains($0.bundle) ? $0.name : nil }
    }
}

/// A process tap that actually started is stronger evidence than TCC preflight.
private let tapAccessLock = NSLock()
private var observedTapAuthorized = false

private func recordTapAccessSuccess() {
    tapAccessLock.lock()
    observedTapAuthorized = true
    tapAccessLock.unlock()
}

@available(macOS 14.2, *)
private final class Engine {
    static let shared = Engine()
    private let logger = Logger(subsystem: "com.whitesticker.controlbox", category: "AppVolume")
    private let lock = NSLock()
    private var sessions: [String: TapSession] = [:]
    private var prefs: [String: Saved] = Engine.loadPrefs()
    private var persistWork: DispatchWorkItem?
    private(set) var lastError: String?

    func snapshot() -> [AttachedAudioApp] {
        let groups = runningApps()
        let outputUID = SystemAudio.defaultOutputUID()
        lock.lock()
        let saved = prefs
        let stale = sessions.keys.filter { id in !groups.contains(where: { $0.id == id }) }
        for id in stale {
            sessions.removeValue(forKey: id)?.invalidate()
        }
        var recreate: [(String, AppGroup, Float)] = []
        if let outputUID {
            for (id, session) in Array(sessions) where session.outputUID != outputUID {
                sessions.removeValue(forKey: id)?.invalidate()
                if let group = groups.first(where: { $0.id == id }), let record = prefs[id] {
                    recreate.append((id, group, record.muted ? 0 : Float(record.volume)))
                }
            }
        }
        lock.unlock()
        if let outputUID {
            for item in recreate {
                startTap(id: item.0, group: item.1, outputUID: outputUID, gain: item.2)
            }
            for group in groups {
                guard let record = saved[group.id], record.needsTap else { continue }
                startTap(
                    id: group.id,
                    group: group,
                    outputUID: outputUID,
                    gain: record.muted ? 0 : Float(record.volume)
                )
            }
        }

        var seen = Set<String>()
        var result: [AttachedAudioApp] = []
        for group in groups {
            seen.insert(group.id)
            let record = saved[group.id]
            result.append(
                AttachedAudioApp(
                    id: group.id,
                    name: group.name,
                    volume: record?.volume ?? 1,
                    isMuted: record?.muted ?? false,
                    isPlaying: group.playing,
                    canAdjust: true
                )
            )
        }
        for (id, record) in saved where !seen.contains(id) {
            result.append(
                AttachedAudioApp(
                    id: id,
                    name: record.name,
                    volume: record.volume,
                    isMuted: record.muted,
                    isPlaying: false,
                    canAdjust: true
                )
            )
        }
        result.sort {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying && !$1.isPlaying }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return result
    }

    func setVolume(_ value: Double, id: String) {
        apply(id: id) { $0.volume = min(max(value, 0), 1) }
    }

    func setMuted(_ muted: Bool, id: String) {
        apply(id: id) { $0.muted = muted }
    }

    private func apply(id: String, mutate: (inout Saved) -> Void) {
        lock.lock()
        var record = prefs[id] ?? Saved(name: id, volume: 1, muted: false)
        mutate(&record)
        prefs[id] = record
        let gain = record.muted ? 0 : Float(record.volume)
        let needsTap = record.needsTap
        let live = sessions[id]
        lock.unlock()
        schedulePersist()

        if let live {
            if needsTap {
                live.setGain(gain)
                lastError = nil
            } else {
                stopTap(id: id)
                lastError = nil
            }
            return
        }

        guard needsTap else {
            lastError = nil
            return
        }
        let groups = runningApps()
        guard let group = groups.first(where: { $0.id == id }) else {
            lastError = nil
            return
        }
        lock.lock()
        if var saved = prefs[id] {
            saved.name = group.name
            prefs[id] = saved
        }
        lock.unlock()
        guard let outputUID = SystemAudio.defaultOutputUID() else {
            lastError = "No default output device."
            return
        }
        startTap(id: id, group: group, outputUID: outputUID, gain: gain)
    }

    private func schedulePersist() {
        persistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let copy = self.prefs
            self.lock.unlock()
            Engine.savePrefs(copy)
        }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func stopTap(id: String) {
        lock.lock()
        let session = sessions.removeValue(forKey: id)
        lock.unlock()
        session?.invalidate()
    }

    private func startTap(id: String, group: AppGroup, outputUID: String, gain: Float) {
        lock.lock()
        if let existing = sessions[id], existing.outputUID == outputUID {
            existing.setGain(gain)
            lock.unlock()
            lastError = nil
            return
        }
        sessions.removeValue(forKey: id)?.invalidate()
        lock.unlock()

        do {
            let session = try TapSession(
                objectIDs: group.objectIDs,
                name: group.name,
                outputUID: outputUID,
                gain: gain
            )
            lock.lock()
            sessions[id] = session
            lastError = nil
            lock.unlock()
            recordTapAccessSuccess()
            logger.info("Tapped \(group.name, privacy: .public) objects=\(group.objectIDs.count)")
        } catch {
            lastError = error.localizedDescription
            logger.error("Tap failed for \(group.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct AppGroup {
        var id: String
        var name: String
        var objectIDs: [AudioObjectID]
        var playing: Bool
    }

    private func runningApps() -> [AppGroup] {
        let selfPID = getpid()
        let running = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var groups: [String: AppGroup] = [:]
        for objectID in processObjectIDs() {
            let pid = pidProperty(objectID)
            if pid == selfPID || pid == 0 { continue }
            let playing = uint32Property(objectID, kAudioProcessPropertyIsRunning) == 1
                || uint32Property(objectID, kAudioProcessPropertyIsRunningOutput) == 1
            guard playing else { continue }

            let resolved = resolvedApp(for: pid, running: running)
            let bundle = resolved?.bundleIdentifier ?? cfStringProperty(objectID, kAudioProcessPropertyBundleID)
            let name = resolved?.localizedName
                ?? bundle.flatMap { Bundle(identifier: $0)?.infoDictionary?["CFBundleName"] as? String }
                ?? bundle
                ?? "PID \(pid)"
            if isSystemDaemon(bundleID: bundle, name: name) { continue }
            let id = bundle ?? "pid:\(resolved?.processIdentifier ?? pid)"
            if var existing = groups[id] {
                if !existing.objectIDs.contains(objectID) {
                    existing.objectIDs.append(objectID)
                }
                existing.playing = true
                groups[id] = existing
            } else {
                groups[id] = AppGroup(id: id, name: name, objectIDs: [objectID], playing: true)
            }
        }
        return Array(groups.values)
    }

    private func resolvedApp(for pid: pid_t, running: [pid_t: NSRunningApplication]) -> NSRunningApplication? {
        if let app = running[pid], app.bundleURL?.pathExtension == "app" {
            return app
        }
        var current = pid
        var seen = Set<pid_t>()
        while current > 1, !seen.contains(current) {
            seen.insert(current)
            if let app = running[current], app.bundleURL?.pathExtension == "app" {
                return app
            }
            guard let parent = parentPID(of: current), parent != current else { break }
            current = parent
        }
        return running[pid]
    }

    private func isSystemDaemon(bundleID: String?, name: String) -> Bool {
        let prefixes = [
            "com.apple.audio", "com.apple.coreaudio", "com.apple.siri", "com.apple.Siri",
            "com.apple.mediaremote", "com.apple.systemsound", "com.apple.corespeech"
        ]
        if let bundleID, prefixes.contains(where: { bundleID.hasPrefix($0) }) {
            return true
        }
        let lowered = name.lowercased()
        return ["coreaudiod", "systemsoundserverd", "audiomxd"].contains { lowered.hasPrefix($0) }
    }

    private func processObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &objects
        ) == noErr else {
            return []
        }
        return objects
    }

    private func pidProperty(_ object: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private func uint32Property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private struct Saved: Codable {
        var name: String
        var volume: Double
        var muted: Bool

        var needsTap: Bool { muted || volume < 0.999 }
    }

    private static let prefsKey = "controlbox.appVolumes.v1"

    private static func loadPrefs() -> [String: Saved] {
        guard let data = UserDefaults.standard.data(forKey: prefsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Saved].self, from: data)) ?? [:]
    }

    private static func savePrefs(_ prefs: [String: Saved]) {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: prefsKey)
        }
    }
}

private func cfStringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else {
        return nil
    }
    return value as String
}

private func parentPID(of pid: pid_t) -> pid_t? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
    let parent = info.kp_eproc.e_ppid
    return parent > 0 && parent != pid ? parent : nil
}

private enum AudioCaptureTCC {
    enum Status {
        case authorized
        case denied
        case unknown
    }

    private static let handle =
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
        ?? dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_NOW)

    private static let service: CFString = {
        if let handle, let symbol = dlsym(handle, "kTCCServiceAudioCapture") {
            return symbol.assumingMemoryBound(to: CFString.self).pointee
        }
        return "kTCCServiceAudioCapture" as CFString
    }()

    static func preflight() -> Status {
        guard let handle,
              let symbol = dlsym(handle, "TCCAccessPreflight") else {
            return .unknown
        }
        let preflight = unsafeBitCast(
            symbol,
            to: (@convention(c) (CFString, CFDictionary?) -> Int32).self
        )
        switch preflight(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request(_ completion: ((Bool) -> Void)? = nil) {
        guard let handle,
              let symbol = dlsym(handle, "TCCAccessRequest") else {
            DispatchQueue.main.async { completion?(false) }
            return
        }
        let request = unsafeBitCast(
            symbol,
            to: (@convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void).self
        )
        request(service, nil) { granted in
            DispatchQueue.main.async { completion?(granted) }
        }
    }
}

private final class StereoPipe {
    private let capacity = 16_384
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private var writeIndex = 0
    private var readIndex = 0
    var gainBits: UInt32 = Float(1).bitPattern
    var format = AudioStreamBasicDescription()

    init() {
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    func write(from input: UnsafePointer<AudioBufferList>?) {
        guard let input else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard !buffers.isEmpty else { return }
        let isFloat = format.mFormatID == 0 || (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let nonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        if isFloat, nonInterleaved, buffers.count >= 2,
           buffers[buffers.count - 2].mNumberChannels == 1,
           buffers[buffers.count - 1].mNumberChannels == 1,
           let leftData = buffers[buffers.count - 2].mData,
           let rightData = buffers[buffers.count - 1].mData {
            let frames = min(
                Int(buffers[buffers.count - 2].mDataByteSize),
                Int(buffers[buffers.count - 1].mDataByteSize)
            ) / MemoryLayout<Float>.size
            writePlanar(
                left: leftData.assumingMemoryBound(to: Float.self),
                right: rightData.assumingMemoryBound(to: Float.self),
                frames: frames
            )
            return
        }
        guard let data = buffers[buffers.count - 1].mData else { return }
        let channels = max(1, Int(buffers[buffers.count - 1].mNumberChannels))
        if isFloat {
            let frames = Int(buffers[buffers.count - 1].mDataByteSize) / (MemoryLayout<Float>.size * channels)
            let samples = data.assumingMemoryBound(to: Float.self)
            writeInterleavedFloat(samples, frames: frames, channels: channels)
            return
        }
        let bytesPerSample = max(1, Int(format.mBitsPerChannel == 0 ? 16 : format.mBitsPerChannel) / 8)
        let frames = Int(buffers[buffers.count - 1].mDataByteSize) / (bytesPerSample * channels)
        writeInterleavedInteger(data, frames: frames, channels: channels, bytesPerSample: bytesPerSample)
    }

    func read(to output: UnsafeMutablePointer<AudioBufferList>?, gain: Float, frameCount: UInt32? = nil) {
        guard let output else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        guard let first = buffers.first, let dst = first.mData else { return }
        let channels = max(1, Int(first.mNumberChannels))
        let frames = Int(frameCount ?? 0) > 0
            ? Int(frameCount!)
            : Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        let samples = dst.assumingMemoryBound(to: Float.self)
        var index = readIndex
        let available = unreadCount(write: writeIndex, read: index)
        for frame in 0..<frames {
            let sampleL: Float
            let sampleR: Float
            if frame < available {
                sampleL = left[index] * gain
                sampleR = right[index] * gain
                index += 1
                if index == capacity { index = 0 }
            } else {
                sampleL = 0
                sampleR = 0
            }
            if buffers.count >= 2,
               first.mNumberChannels == 1,
               let rightData = buffers[1].mData {
                samples[frame] = sampleL
                rightData.assumingMemoryBound(to: Float.self)[frame] = sampleR
            } else {
                let base = frame * channels
                for channel in 0..<channels { samples[base + channel] = 0 }
                samples[base] = sampleL
                if channels > 1 { samples[base + 1] = sampleR }
            }
        }
        readIndex = index
        if buffers.count > 2 {
            for extra in 2..<buffers.count {
                if let data = buffers[extra].mData {
                    memset(data, 0, Int(buffers[extra].mDataByteSize))
                }
            }
        }
    }

    private func writeInterleavedFloat(_ samples: UnsafePointer<Float>, frames: Int, channels: Int) {
        var index = writeIndex
        for frame in 0..<frames {
            left[index] = samples[frame * channels]
            right[index] = channels > 1 ? samples[frame * channels + 1] : samples[frame * channels]
            index += 1
            if index == capacity { index = 0 }
        }
        writeIndex = index
    }

    private func writeInterleavedInteger(
        _ data: UnsafeMutableRawPointer,
        frames: Int,
        channels: Int,
        bytesPerSample: Int
    ) {
        var index = writeIndex
        let scale: Float = bytesPerSample >= 3 ? Float(1 << 31) : Float(Int16.max)
        for frame in 0..<frames {
            left[index] = integerSample(data, frame: frame, channel: 0, channels: channels, bytes: bytesPerSample, scale: scale)
            right[index] = channels > 1
                ? integerSample(data, frame: frame, channel: 1, channels: channels, bytes: bytesPerSample, scale: scale)
                : left[index]
            index += 1
            if index == capacity { index = 0 }
        }
        writeIndex = index
    }

    private func integerSample(
        _ data: UnsafeMutableRawPointer,
        frame: Int,
        channel: Int,
        channels: Int,
        bytes: Int,
        scale: Float
    ) -> Float {
        let offset = (frame * channels + channel) * bytes
        if bytes >= 4 {
            return Float(data.load(fromByteOffset: offset, as: Int32.self)) / scale
        }
        return Float(data.load(fromByteOffset: offset, as: Int16.self)) / scale
    }

    private func writePlanar(left srcL: UnsafePointer<Float>, right srcR: UnsafePointer<Float>, frames: Int) {
        var index = writeIndex
        for frame in 0..<frames {
            left[index] = srcL[frame]
            right[index] = srcR[frame]
            index += 1
            if index == capacity { index = 0 }
        }
        writeIndex = index
    }

    private func unreadCount(write: Int, read: Int) -> Int {
        if write >= read { return write - read }
        return capacity - read + write
    }
}

@available(macOS 14.2, *)
private final class TapSession {
    let outputUID: String
    private var gainBits: UInt32
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var captureProcID: AudioDeviceIOProcID?
    private var outputUnit: AudioUnit?
    private let queue = DispatchQueue(label: "controlbox.app-volume-tap")
    private let pipe = StereoPipe()

    func setGain(_ value: Float) {
        gainBits = value.bitPattern
        pipe.gainBits = value.bitPattern
    }

    init(objectIDs: [AudioObjectID], name: String, outputUID: String, gain: Float) throws {
        self.outputUID = outputUID
        self.gainBits = gain.bitPattern
        pipe.gainBits = gain.bitPattern
        guard !objectIDs.isEmpty else {
            throw MixerError("That app has no audio process to tap.")
        }
        if AudioCaptureTCC.preflight() != .authorized {
            AudioCaptureTCC.request()
        }

        let tap = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        tap.uuid = UUID()
        tap.name = "Control Box \(name)"
        tap.muteBehavior = .mutedWhenTapped
        tap.isPrivate = true
        tap.deviceUID = outputUID
        var createdTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(tap, &createdTap)
        guard tapStatus == noErr, createdTap != kAudioObjectUnknown else {
            throw MixerError("Could not tap \(name) (status \(tapStatus)). Grant System Audio Recording if macOS asked.")
        }
        tapID = createdTap
        if let asbd = Self.tapFormat(createdTap) {
            pipe.format = asbd
        }

        let tapKey = Self.tapUID(createdTap) ?? tap.uuid.uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Control Box Mix \(name)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapKey,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        var createdAggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &createdAggregate)
        guard aggregateStatus == noErr, createdAggregate != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw MixerError("Could not route \(name) to the speakers (\(aggregateStatus)).")
        }
        aggregateID = createdAggregate
        guard Self.waitUntilAlive(createdAggregate, timeout: 2) else {
            invalidate()
            throw MixerError("Mixer for \(name) never came online.")
        }

        var captureID: AudioDeviceIOProcID?
        let captureStatus = AudioDeviceCreateIOProcIDWithBlock(&captureID, aggregateID, queue) { [weak self] _, input, _, output, _ in
            guard let self else { return }
            self.pipe.write(from: input)
            Self.silence(output)
        }
        guard captureStatus == noErr, let captureID else {
            invalidate()
            throw MixerError("Could not start the mixer for \(name).")
        }
        captureProcID = captureID

        let playStatus = AudioDeviceStart(aggregateID, captureID)
        guard playStatus == noErr else {
            invalidate()
            throw MixerError("Mixer start failed for \(name) (\(playStatus)).")
        }

        guard let outputDevice = SystemAudio.device(uid: outputUID) else {
            invalidate()
            throw MixerError("Could not find the speakers to play back \(name).")
        }
        do {
            let sampleRate = pipe.format.mSampleRate > 0
                ? pipe.format.mSampleRate
                : SystemAudio.nominalSampleRate(outputDevice)
            outputUnit = try Self.makeOutputUnit(pipe: pipe, deviceID: outputDevice, sampleRate: sampleRate)
        } catch {
            invalidate()
            throw error
        }
    }

    private static let outputRender: AURenderCallback = { ref, _, _, _, frameCount, ioData in
        guard let ioData else { return noErr }
        let pipe = Unmanaged<StereoPipe>.fromOpaque(ref).takeUnretainedValue()
        pipe.read(to: ioData, gain: Float(bitPattern: pipe.gainBits), frameCount: frameCount)
        return noErr
    }

    private static func makeOutputUnit(pipe: StereoPipe, deviceID: AudioDeviceID, sampleRate: Double) throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw MixerError("No output unit.")
        }
        var unit: AudioUnit?
        guard AudioComponentInstanceNew(component, &unit) == noErr, let unit else {
            throw MixerError("Could not open the speakers.")
        }
        func fail(_ message: String) -> MixerError {
            AudioComponentInstanceDispose(unit)
            return MixerError(message)
        }
        var enable: UInt32 = 1
        var disable: UInt32 = 0
        let ioSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &enable,
            ioSize
        ) == noErr else {
            throw fail("Could not enable speaker output.")
        }
        _ = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &disable,
            ioSize
        )
        var device = deviceID
        guard AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        ) == noErr else {
            throw fail("Could not attach the speakers.")
        }
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate > 0 ? sampleRate : 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        guard AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ) == noErr else {
            throw fail("Could not set speaker format.")
        }
        var callback = AURenderCallbackStruct(
            inputProc: outputRender,
            inputProcRefCon: Unmanaged.passUnretained(pipe).toOpaque()
        )
        guard AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        ) == noErr else {
            throw fail("Could not attach the speaker callback.")
        }
        guard AudioUnitInitialize(unit) == noErr else {
            throw fail("Could not initialize the speakers.")
        }
        guard AudioOutputUnitStart(unit) == noErr else {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            throw MixerError("Could not start speaker playback.")
        }
        return unit
    }

    private static func tapFormat(_ tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd) == noErr else {
            return nil
        }
        return asbd
    }

    private static func tapUID(_ tapID: AudioObjectID) -> String? {
        cfStringProperty(tapID, kAudioTapPropertyUID)
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if let outputUnit {
            AudioOutputUnitStop(outputUnit)
            AudioUnitUninitialize(outputUnit)
            AudioComponentInstanceDispose(outputUnit)
            self.outputUnit = nil
        }
        if let captureProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, captureProcID)
            AudioDeviceDestroyIOProcID(aggregateID, captureProcID)
            self.captureProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    private static func waitUntilAlive(_ device: AudioObjectID, timeout: TimeInterval) -> Bool {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var alive: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive) == noErr, alive != 0 {
                return true
            }
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        return false
    }

    private static func silence(_ output: UnsafeMutablePointer<AudioBufferList>?) {
        guard let output else { return }
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }
}

private struct MixerError: LocalizedError {
    var errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
