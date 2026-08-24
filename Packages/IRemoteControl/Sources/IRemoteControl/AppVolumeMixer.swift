import AppKit
import AudioToolbox
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

    public static var hasCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public static func requestCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
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

@available(macOS 14.2, *)
private final class Engine {
    static let shared = Engine()
    private let logger = Logger(subsystem: "com.iremote.app", category: "AppVolume")
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

    private static let prefsKey = "IRemote.appVolumes.v1"

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

@available(macOS 14.2, *)
private final class TapSession {
    let outputUID: String
    private var gainBits: UInt32
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "iremote.app-volume-tap")
    private var leftChannel = 0
    private var rightChannel = 1

    func setGain(_ value: Float) {
        gainBits = value.bitPattern
    }

    init(objectIDs: [AudioObjectID], name: String, outputUID: String, gain: Float) throws {
        self.outputUID = outputUID
        self.gainBits = gain.bitPattern
        guard !objectIDs.isEmpty else {
            throw MixerError("That app has no audio process to tap.")
        }

        let (tap, createdTap) = try Self.makeTap(objectIDs: objectIDs, outputUID: outputUID, name: name)
        tapID = createdTap

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VibeRemote Mix \(name)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceClockDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID,
                    kAudioSubDeviceDriftCompensationKey: false
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tap.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: !Self.isBluetooth(outputUID)
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

        let stereo = Self.preferredStereoChannels(outputUID)
        leftChannel = stereo.left
        rightChannel = stereo.right

        var procID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, output, _ in
            guard let self else {
                Self.silence(output)
                return
            }
            Self.render(
                input,
                to: output,
                gain: Float(bitPattern: self.gainBits),
                left: self.leftChannel,
                right: self.rightChannel
            )
        }
        guard ioStatus == noErr, let procID else {
            invalidate()
            throw MixerError("Could not start the mixer for \(name).")
        }
        ioProcID = procID
        Self.ignoreHardwareInputs(aggregateID: aggregateID, procID: procID)

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            invalidate()
            throw MixerError("Mixer start failed for \(name) (\(startStatus)).")
        }
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
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

    private static func makeTap(
        objectIDs: [AudioObjectID],
        outputUID: String,
        name: String
    ) throws -> (CATapDescription, AudioObjectID) {
        if let stream = firstOutputStreamIndex(outputUID) {
            let streamTap = CATapDescription(processes: objectIDs, deviceUID: outputUID, stream: UInt(stream))
            streamTap.uuid = UUID()
            streamTap.muteBehavior = .mutedWhenTapped
            streamTap.isPrivate = true
            var tapID = AudioObjectID(kAudioObjectUnknown)
            if AudioHardwareCreateProcessTap(streamTap, &tapID) == noErr, tapID != kAudioObjectUnknown {
                return (streamTap, tapID)
            }
        }

        let mixdown = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        mixdown.uuid = UUID()
        mixdown.muteBehavior = .mutedWhenTapped
        mixdown.isPrivate = true
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(mixdown, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            throw MixerError("Could not tap \(name) (status \(status)). Grant Screen & System Audio Recording if macOS asked.")
        }
        return (mixdown, tapID)
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

    private static func render(
        _ input: UnsafePointer<AudioBufferList>?,
        to output: UnsafeMutablePointer<AudioBufferList>?,
        gain: Float,
        left: Int,
        right: Int
    ) {
        guard let input, let output else { return }
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)
        let inCount = inList.count
        let outCount = outList.count
        for outputIndex in 0..<outCount {
            let dest = outList[outputIndex]
            guard let dst = dest.mData else { continue }
            let inputIndex = inCount > outCount ? inCount - outCount + outputIndex : outputIndex
            guard inputIndex < inCount, let src = inList[inputIndex].mData else {
                memset(dst, 0, Int(dest.mDataByteSize))
                continue
            }
            let source = inList[inputIndex]
            let inChannels = max(1, Int(source.mNumberChannels))
            let outChannels = max(1, Int(dest.mNumberChannels))
            let inFrames = Int(source.mDataByteSize) / (MemoryLayout<Float>.size * inChannels)
            let outFrames = Int(dest.mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
            let frames = min(inFrames, outFrames)
            let srcFloat = src.assumingMemoryBound(to: Float.self)
            let dstFloat = dst.assumingMemoryBound(to: Float.self)
            let safeLeft = min(max(left, 0), max(outChannels - 1, 0))
            let safeRight = min(max(right, 0), max(outChannels - 1, 0))

            if inChannels == outChannels {
                for frame in 0..<frames {
                    let base = frame * inChannels
                    for channel in 0..<inChannels {
                        dstFloat[base + channel] = srcFloat[base + channel] * gain
                    }
                }
            } else if inChannels == 2, outChannels > 2 {
                for frame in 0..<frames {
                    let inBase = frame * 2
                    let outBase = frame * outChannels
                    for channel in 0..<outChannels { dstFloat[outBase + channel] = 0 }
                    dstFloat[outBase + safeLeft] = srcFloat[inBase] * gain
                    dstFloat[outBase + safeRight] = srcFloat[inBase + 1] * gain
                }
            } else if inChannels == 1, outChannels > 1 {
                for frame in 0..<frames {
                    let sample = srcFloat[frame] * gain
                    let outBase = frame * outChannels
                    for channel in 0..<outChannels { dstFloat[outBase + channel] = 0 }
                    dstFloat[outBase + safeLeft] = sample
                    dstFloat[outBase + safeRight] = sample
                }
            } else {
                for frame in 0..<frames {
                    let inBase = frame * inChannels
                    let outBase = frame * outChannels
                    let copied = min(inChannels, outChannels)
                    for channel in 0..<copied {
                        dstFloat[outBase + channel] = srcFloat[inBase + channel] * gain
                    }
                    if copied < outChannels {
                        for channel in copied..<outChannels { dstFloat[outBase + channel] = 0 }
                    }
                }
            }
            let written = frames * outChannels
            let total = Int(dest.mDataByteSize) / MemoryLayout<Float>.size
            if written < total {
                memset(dstFloat.advanced(by: written), 0, (total - written) * MemoryLayout<Float>.size)
            }
        }
    }

    private static func silence(_ output: UnsafeMutablePointer<AudioBufferList>?) {
        guard let output else { return }
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }

    private static func ignoreHardwareInputs(aggregateID: AudioObjectID, procID: AudioDeviceIOProcID) {
        let inputCount = streamCount(aggregateID, scope: kAudioDevicePropertyScopeInput)
        let outputCount = streamCount(aggregateID, scope: kAudioDevicePropertyScopeOutput)
        guard inputCount > 0, outputCount > 0, inputCount > outputCount else { return }
        let used = min(outputCount, inputCount)
        let header = MemoryLayout<UnsafeMutableRawPointer>.size + MemoryLayout<UInt32>.size
        let total = header + inputCount * MemoryLayout<UInt32>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: total, alignment: MemoryLayout<UnsafeMutableRawPointer>.alignment)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(inputCount), toByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        let flags = raw.advanced(by: header)
        for index in 0..<inputCount {
            let on: UInt32 = index >= inputCount - used ? 1 : 0
            flags.advanced(by: index * MemoryLayout<UInt32>.size).storeBytes(of: on, as: UInt32.self)
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIOProcStreamUsage,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(total), raw)
    }

    private static func streamCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private static func firstOutputStreamIndex(_ uid: String) -> Int? {
        guard let device = SystemAudio.device(uid: uid) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let count = Int(size) / MemoryLayout<AudioStreamID>.size
        var streams = [AudioStreamID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr else {
            return 0
        }
        for (index, stream) in streams.enumerated() {
            var direction: UInt32 = 1
            var directionSize = UInt32(MemoryLayout<UInt32>.size)
            var directionAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyDirection,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(stream, &directionAddress, 0, nil, &directionSize, &direction) == noErr,
               direction == 0 {
                return index
            }
        }
        return 0
    }

    private static func preferredStereoChannels(_ uid: String) -> (left: Int, right: Int) {
        guard let device = SystemAudio.device(uid: uid) else { return (0, 1) }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var channels: [UInt32] = [1, 2]
        var size = UInt32(MemoryLayout<UInt32>.size * 2)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &channels) == noErr else {
            return (0, 1)
        }
        return (max(0, Int(channels[0]) - 1), max(0, Int(channels[1]) - 1))
    }

    private static func isBluetooth(_ uid: String) -> Bool {
        guard let device = SystemAudio.device(uid: uid) else { return true }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else {
            return true
        }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}

private struct MixerError: LocalizedError {
    var errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
