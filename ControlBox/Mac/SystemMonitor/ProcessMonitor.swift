import Foundation
import Darwin
import AppKit

// On-demand "who's using the most X right now" lookups, used by each
// section's detail submenu (via `TopProcessFeed`, only while that submenu is
// open). Deliberately NOT sampled on SystemMonitor's continuous per-second
// polling loop: walking every process costs far more than the handful of
// sysctl/mach calls the other monitors make.
//
// CPU comes from `/bin/ps`, which is setuid root. libproc from this
// unprivileged app cannot read root- or system-user processes
// (WindowServer, kernel_task, mds_stores: about a third of all pids), so a
// libproc ranking silently skipped the heaviest users. `ps` %CPU is the
// kernel's decaying per-process average, the same figure `ps` and `top`
// print. One call is ~20 ms.
//
// Memory and energy come from a long-lived `/usr/bin/top` (`TopStream`),
// also setuid: memory is the physical footprint and energy is the
// Energy Impact score, the two figures Activity Monitor shows. `ps` only
// has RSS, which counts shared pages in every process that maps them.
//
// Disk I/O has no setuid tool, so it stays on libproc (own-user processes
// only) and ranks over a rolling ~10 s window across refreshes: a 0.5 s
// window caught 0-3 processes, 2 s about 8, 10 s about 12.
//
// Network has no public per-process API. One-shot `nettop` prints
// cumulative per-process bytes (~20 ms through a pipe); two snapshots give
// current speed. Its own delta mode (`-d`, more than one sample) burns
// about a core per sample, so never ask nettop for a second sample.
//
// One instance per `TopProcessFeed`, only touched on the feed queue.
final class ProcessMonitor {
    struct TopProcess: Sendable, Identifiable {
        var id: pid_t { pid }
        var pid: pid_t
        var name: String
        var value: Double
    }

    struct PSRow: Equatable {
        var pid: pid_t
        var cpuPercent: Double
        var residentBytes: UInt64
        var name: String
    }

    private var disk = RateWindow(span: 10)
    private var network = RateWindow(span: 4)
    private var networkNames: [pid_t: String] = [:]

    /// Polled kinds only; memory and energy stream through `TopStream`.
    func top(_ kind: TopProcessKind, count: Int) -> [TopProcess] {
        switch kind {
        case .cpu: return topCPUProcesses(count: count)
        case .disk: return topDiskProcesses(count: count)
        case .network: return topNetworkProcesses(count: count)
        case .memory, .energy: return []
        }
    }

    /// Drops rolling-window state so the next open starts a fresh window.
    func reset() {
        disk.reset()
        network.reset()
    }

    /// Walks the ranked list until `count` names resolve, so a process that
    /// exits mid-sample does not shorten the list.
    private func named(
        _ ranked: [(pid: pid_t, value: Double)],
        count: Int
    ) -> [TopProcess] {
        var result: [TopProcess] = []
        for entry in ranked {
            guard let name = Self.processName(pid: entry.pid) else { continue }
            result.append(TopProcess(pid: entry.pid, name: name, value: entry.value))
            if result.count == count { break }
        }
        return result
    }

    // MARK: - CPU (via setuid `/bin/ps`)

    func topCPUProcesses(count: Int = 5) -> [TopProcess] {
        psRows()
            .filter { $0.cpuPercent > 0 }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(count)
            .map { TopProcess(pid: $0.pid, name: $0.name, value: $0.cpuPercent) }
    }

    private func psRows() -> [PSRow] {
        guard let output = Self.run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm="]) else { return [] }
        return Self.parsePS(output)
    }

    /// `ps -Aceo pid=,pcpu=,rss=,comm=`: no header; pid, %CPU, RSS in KiB,
    /// then the command name, which can contain spaces
    /// ("Cursor Helper (Renderer)").
    static func parsePS(_ output: String) -> [PSRow] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = pid_t(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKiB = UInt64(fields[2]) else { return nil }
            let name = fields[3].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return PSRow(pid: pid, cpuPercent: cpu, residentBytes: rssKiB * 1024, name: name)
        }
    }

    // MARK: - Disk

    func topDiskProcesses(count: Int = 5) -> [TopProcess] {
        if disk.isEmpty {
            _ = disk.add(allDiskIOBytes())
            Thread.sleep(forTimeInterval: 0.5)
        }
        return named(disk.add(allDiskIOBytes()), count: count)
    }

    private func allDiskIOBytes() -> [pid_t: UInt64] {
        var result: [pid_t: UInt64] = [:]
        for pid in allPIDs() {
            guard let bytes = diskIOBytes(pid: pid) else { continue }
            result[pid] = bytes
        }
        return result
    }

    // MARK: - Network (best-effort via `nettop`)

    /// Current speed (bytes in + out per second over the last ~4 s), not
    /// lifetime totals. A process whose total drops (sockets closed) counts
    /// as idle for that window.
    func topNetworkProcesses(count: Int = 5) -> [TopProcess] {
        if network.isEmpty {
            _ = network.add(nettopBytes())
            Thread.sleep(forTimeInterval: 1)
        }
        let ranked = network.add(nettopBytes())
        return ranked.prefix(count).compactMap { entry in
            guard let name = Self.processName(pid: entry.pid) ?? networkNames[entry.pid] else { return nil }
            return TopProcess(pid: entry.pid, name: name, value: entry.value)
        }
    }

    /// `-n` matters: without it nettop resolves addresses and every call
    /// takes ~5 s instead of ~17 ms.
    private func nettopBytes() -> [pid_t: UInt64] {
        guard let output = Self.run("/usr/bin/nettop", ["-P", "-x", "-n", "-l", "1", "-J", "bytes_in,bytes_out"]) else {
            return [:]
        }
        let rows = Self.parseNettop(output)
        networkNames = rows.mapValues(\.name)
        return rows.mapValues(\.bytes)
    }

    /// Reads stdout to EOF before waiting: output past the 64 KiB pipe buffer
    /// would otherwise block the child forever.
    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let outPipe = Pipe()
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = outPipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // `nettop -P -x -l 1 -J bytes_in,bytes_out` prints one header line
    // ("... bytes_in  bytes_out", no comma despite `-J`, and no label at
    // all over the name column) followed by one row per process. This is
    // NOT CSV -- it's whitespace-column-aligned text -- an earlier version
    // assumed a "time,bytes_in,bytes_out" CSV header that never actually
    // appears, so every call silently returned an empty list.
    /// Cumulative bytes in + out per pid. nettop names are cut at 15
    /// characters, so they are only the fallback for `proc_name`.
    static func parseNettop(_ output: String) -> [pid_t: (name: String, bytes: UInt64)] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        func isHeader(_ line: String) -> Bool {
            line.contains("bytes_in") && line.contains("bytes_out")
        }
        guard let headerIndex = lines.firstIndex(where: isHeader) else { return [:] }

        var rows: [pid_t: (name: String, bytes: UInt64)] = [:]
        for line in lines[(headerIndex + 1)...] {
            if isHeader(line) { break }
            // The process field is "name.pid" and can itself contain
            // spaces (e.g. "Notion Helper.13665"), so take the last two
            // whitespace-separated tokens as the byte counts and treat
            // everything before them as the combined name+pid field.
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 3,
                  let bytesOut = UInt64(tokens[tokens.count - 1]),
                  let bytesIn = UInt64(tokens[tokens.count - 2]) else { continue }

            let nameAndPID = tokens[0..<(tokens.count - 2)].joined(separator: " ")
            var nameParts = nameAndPID.split(separator: ".").map(String.init)
            guard nameParts.count > 1, let pid = pid_t(nameParts.removeLast()), pid > 0 else { continue }
            let name = nameParts.joined(separator: ".")
            guard !name.isEmpty else { continue }
            rows[pid] = (name, bytesIn + bytesOut)
        }
        return rows
    }

    // MARK: - Icons

    // Prefers the real app icon (matches Dock/Finder) for foreground/GUI
    // apps; falls back to the generic executable icon Activity Monitor
    // shows for background daemons that aren't registered running apps.
    static func icon(for pid: pid_t) -> NSImage? {
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            return icon
        }
        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        guard len > 0 else { return nil }
        return NSWorkspace.shared.icon(forFile: String(cString: pathBuf))
    }

    // MARK: - libproc helpers

    private func allPIDs() -> [pid_t] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        let capacity = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: capacity)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        guard actualSize > 0 else { return [] }
        let count = Int(actualSize) / MemoryLayout<pid_t>.size
        return pids.prefix(count).filter { $0 > 0 }
    }

    /// Full name for own-user processes; nil for root and other users'.
    static func processName(pid: pid_t) -> String? {
        var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let len = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        guard len > 0 else { return nil }
        return String(cString: nameBuf)
    }

    private func diskIOBytes(pid: pid_t) -> UInt64? {
        // `rusage_info_t` is `UnsafeMutableRawPointer?` and the C signature
        // is nominally "pointer to that" (a double pointer) -- but the real
        // ABI (matching how Apple's own examples call this) is that the
        // kernel writes `sizeof(rusage_info_v4)` bytes directly at the
        // address you pass, not through a second level of indirection. This
        // reinterprets the pointer to `info` itself, matching the C idiom
        // `(rusage_info_t *)&info`. An earlier version instead created a
        // separate 8-byte pointer variable and passed *its* address, so the
        // kernel wrote a ~200-byte struct into that 8-byte stack slot --
        // a stack buffer overflow that crashed the app (SIGABRT,
        // `__stack_chk_fail`).
        var info = rusage_info_v4()
        let result: Int32 = withUnsafeMutablePointer(to: &info) { infoPtr -> Int32 in
            infoPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPtr)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_diskio_bytesread + info.ri_diskio_byteswritten
    }
}

/// Cumulative per-pid byte counters turned into a rate. The base is the
/// newest reading at least `span` old, so with 2 s refreshes the window is
/// `span` once warm.
private struct RateWindow {
    let span: TimeInterval
    private var readings: [(date: Date, bytes: [pid_t: UInt64])] = []

    init(span: TimeInterval) {
        self.span = span
    }

    var isEmpty: Bool { readings.isEmpty }

    mutating func reset() {
        readings = []
    }

    /// Bytes per second since the base reading, highest first.
    mutating func add(_ bytes: [pid_t: UInt64]) -> [(pid: pid_t, value: Double)] {
        let now = Date()
        readings.append((now, bytes))
        while readings.count > 2, now.timeIntervalSince(readings[1].date) >= span {
            readings.removeFirst()
        }
        let base = readings[0]
        let elapsed = now.timeIntervalSince(base.date)
        guard elapsed > 0 else { return [] }
        return bytes.compactMap { pid, current -> (pid: pid_t, value: Double)? in
            guard let previous = base.bytes[pid], current > previous else { return nil }
            return (pid, Double(current - previous) / elapsed)
        }
        .sorted { $0.value > $1.value }
    }
}

/// One long-lived `/usr/bin/top -l 0` sorted by a single key. top's first
/// sample walks every process's memory map (~0.75 s of system time); later
/// samples cost ~0.12 s, so a stream beats one spawn per refresh. top
/// flushes each sample to the pipe and dies on SIGPIPE when Control Box
/// goes away, so a crash cannot orphan it.
final class TopStream {
    private let process = Process()
    private let pipe = Pipe()

    /// Every running stream's `top`, so one stream's process (still
    /// lingering after its submenu hid) is not listed by another.
    private static let lock = NSLock()
    private static var runningPIDs: Set<pid_t> = []

    private static func isStream(_ pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runningPIDs.contains(pid)
    }

    /// `onSample` runs on the pipe's handler queue. `skipFirst` drops the
    /// first sample, which is all zeros for rate columns such as `power`.
    init(
        sortKey: String,
        interval: TimeInterval,
        count: Int,
        skipFirst: Bool,
        onSample: @escaping ([ProcessMonitor.TopProcess]) -> Void
    ) {
        // Two extra rows so our own `top` processes can be dropped.
        let parser = TopSampleParser(rowCount: count + 2, skipFirst: skipFirst)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = [
            "-l", "0", "-s", String(Int(interval)), "-o", sortKey,
            "-n", String(count + 2), "-stats", "pid,\(sortKey),command",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            for rows in parser.feed(data) {
                onSample(Array(rows.filter { !Self.isStream($0.pid) }.prefix(count)))
            }
        }
        do {
            try process.run()
            Self.lock.lock()
            Self.runningPIDs.insert(process.processIdentifier)
            Self.lock.unlock()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            onSample([])
        }
    }

    deinit {
        stop()
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        guard process.isRunning else { return }
        Self.lock.lock()
        Self.runningPIDs.remove(process.processIdentifier)
        Self.lock.unlock()
        process.terminate()
    }
}

/// Splits `top -l 0 -stats pid,<key>,command` output into samples. Each
/// sample is a summary block, a "PID ..." header, then `rowCount` rows.
/// Only touched on the pipe's handler queue.
private final class TopSampleParser {
    private let rowCount: Int
    private var skip: Bool
    private var partial = Data()
    private var rows: [ProcessMonitor.TopProcess]?

    init(rowCount: Int, skipFirst: Bool) {
        self.rowCount = rowCount
        skip = skipFirst
    }

    func feed(_ data: Data) -> [[ProcessMonitor.TopProcess]] {
        partial.append(data)
        guard let newline = partial.lastIndex(of: 0x0A) else { return [] }
        let text = String(decoding: partial[..<newline], as: UTF8.self)
        partial = Data(partial[partial.index(after: newline)...])

        var samples: [[ProcessMonitor.TopProcess]] = []
        func finish() {
            guard let done = rows else { return }
            rows = nil
            if skip { skip = false } else { samples.append(done) }
        }
        for line in text.split(separator: "\n") {
            if line.hasPrefix("PID") {
                rows = []
            } else if line.hasPrefix("Processes:") {
                finish()
            } else if rows != nil, let row = Self.row(line) {
                rows?.append(row)
                if rows?.count == rowCount { finish() }
            }
        }
        return samples
    }

    /// "664    1171M- WindowServer" or "664    28.6  WindowServer". top cuts
    /// the command at 16 characters, so it is only the fallback name.
    private static func row(_ line: Substring) -> ProcessMonitor.TopProcess? {
        let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard fields.count == 3, let pid = pid_t(fields[0]), let value = value(fields[1]) else { return nil }
        let command = fields[2].trimmingCharacters(in: .whitespaces)
        let name = ProcessMonitor.processName(pid: pid) ?? command
        guard !name.isEmpty else { return nil }
        return ProcessMonitor.TopProcess(pid: pid, name: name, value: value)
    }

    /// Plain numbers ("28.6") or binary sizes ("1171M+", "2720K", "1.2G");
    /// a trailing +/- is top's change marker.
    private static func value(_ field: Substring) -> Double? {
        var text = field
        while let last = text.last, last == "+" || last == "-" { text.removeLast() }
        let units: [Character: Double] = ["B": 1, "K": 0x1p10, "M": 0x1p20, "G": 0x1p30, "T": 0x1p40]
        if let last = text.last, let unit = units[last] {
            return Double(text.dropLast()).map { $0 * unit }
        }
        return Double(text)
    }
}

enum TopProcessKind {
    case cpu, memory, energy, disk, network

    var refreshInterval: TimeInterval { 2 }

    /// `top -o` key for kinds read from a long-lived `TopStream`.
    var streamKey: String? {
        switch self {
        case .memory: return "mem"
        case .energy: return "power"
        case .cpu, .disk, .network: return nil
        }
    }
}

/// One detail submenu's top-process list. Main thread only. Polled kinds
/// sample on a shared serial queue (never the Swift cooperative pool: the
/// first disk and network samples `Thread.sleep` and `ps` / `nettop` block
/// on a child process) and skip a refresh while the previous one is still
/// running; memory and energy stream from `TopStream`. Keeps the last
/// result across opens so a reopen shows rows immediately. App icons
/// resolve once per pid when a result lands, not on every SwiftUI render.
final class TopProcessFeed: ObservableObject {
    static let slotCount = 5

    /// A stream outlives its submenu this long, so sweeping the pointer
    /// across rows does not pay top's ~0.75 s first sample on every pass.
    private static let streamLinger: TimeInterval = 10

    let kind: TopProcessKind
    @Published private(set) var processes: [ProcessMonitor.TopProcess] = []
    @Published private(set) var loaded = false
    private(set) var icons: [pid_t: NSImage] = [:]

    private static let queue = DispatchQueue(label: "com.local.top.processes", qos: .utility)
    private let monitor = ProcessMonitor()
    private var timer: Timer?
    private var inFlight = false
    private var stream: TopStream?
    private var lingerTimer: Timer?

    init(kind: TopProcessKind) {
        self.kind = kind
    }

    func start() {
        lingerTimer?.invalidate()
        lingerTimer = nil
        if let key = kind.streamKey {
            guard stream == nil else { return }
            stream = TopStream(
                sortKey: key,
                interval: kind.refreshInterval,
                count: Self.slotCount,
                skipFirst: kind == .energy
            ) { [weak self] result in
                DispatchQueue.main.async { self?.apply(result) }
            }
            return
        }
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: kind.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        Self.queue.async { [monitor] in monitor.reset() }
        guard stream != nil, lingerTimer == nil else { return }
        let linger = Timer(timeInterval: Self.streamLinger, repeats: false) { [weak self] _ in
            self?.stream?.stop()
            self?.stream = nil
            self?.lingerTimer = nil
        }
        RunLoop.main.add(linger, forMode: .common)
        lingerTimer = linger
    }

    private func refresh() {
        guard !inFlight else { return }
        inFlight = true
        let kind = kind
        Self.queue.async { [weak self, monitor] in
            let result = monitor.top(kind, count: Self.slotCount)
            DispatchQueue.main.async {
                self?.apply(result)
            }
        }
    }

    private func apply(_ result: [ProcessMonitor.TopProcess]) {
        inFlight = false
        var nextIcons: [pid_t: NSImage] = [:]
        for proc in result {
            if let icon = icons[proc.pid] ?? ProcessMonitor.icon(for: proc.pid) {
                nextIcons[proc.pid] = icon
            }
        }
        icons = nextIcons
        processes = result
        loaded = true
    }
}
