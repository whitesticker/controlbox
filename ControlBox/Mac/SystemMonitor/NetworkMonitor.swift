import Foundation
import Darwin
import SystemConfiguration

// Collects per-interface network throughput using 64-bit cumulative byte
// counters from the routing socket interface list (NET_RT_IFLIST2), which
// avoids the 32-bit wraparound that getifaddrs' legacy if_data counters can
// suffer from on long-uptime machines. IPv4 addresses are resolved
// separately via getifaddrs (AF_INET).
//
// Contract: final class NetworkMonitor { init(); func sample() -> NetworkSample }
// Called ~1/sec from a background queue. Rates are computed from the delta
// of byte counters between successive calls, divided by elapsed wall-clock
// time. The first call always returns zero rates (no prior sample to diff
// against). Never crashes; returns safe defaults on failure.
final class NetworkMonitor {

    // Raw cumulative counters captured for one interface at one point in time.
    private struct Counters {
        var inBytes: UInt64
        var outBytes: UInt64
    }

    // Last-seen cumulative counters per interface name, used to compute deltas.
    private var lastCounters: [String: Counters] = [:]

    // Timestamp of the previous sample (mach continuous time based, via
    // Date for simplicity/portability).
    private var lastTimestamp: Date?

    // Accumulated positive deltas since the monitor was created (i.e. since
    // app launch), used for sessionUp / sessionDown.
    private var sessionUpTotal: UInt64 = 0
    private var sessionDownTotal: UInt64 = 0

    // Whether this is the very first sample (so we can suppress rate
    // computation and just seed the counters).
    private var isFirstSample = true

    /// System Settings' name and type per BSD name, re-read only when the
    /// set of interfaces changes (a dongle, VPN, or hotspot comes or goes).
    private var interfaceInfo: [String: (kind: NetworkInterfaceKind, name: String)] = [:]
    private var interfaceInfoNames: Set<String> = []

    init() {}

    func sample() -> NetworkSample {
        var result = NetworkSample()

        let now = Date()
        let elapsed: Double
        if let last = lastTimestamp {
            elapsed = now.timeIntervalSince(last)
        } else {
            elapsed = 0
        }

        // 1. Read cumulative 64-bit byte counters per interface from the
        //    routing socket interface list.
        let currentCounters = readInterfaceCounters()
        let names = Set(currentCounters.keys)
        if names != interfaceInfoNames {
            interfaceInfo = Self.readInterfaceInfo()
            interfaceInfoNames = names
        }

        // 2. Read IPv4 addresses per interface via getifaddrs.
        let ipv4ByInterface = readIPv4Addresses()

        // 3. Build per-interface samples, computing rates from deltas where
        //    we have a previous sample to diff against.
        var interfaceSamples: [NetworkInterfaceSample] = []
        var aggregateUpRate: Double = 0
        var aggregateDownRate: Double = 0
        var aggregateTotalUp: UInt64 = 0
        var aggregateTotalDown: UInt64 = 0

        // Iterate in a stable order (sorted by name) for deterministic output.
        for name in currentCounters.keys.sorted() {
            guard let counters = currentCounters[name] else { continue }
            guard !isLoopback(name) else { continue }

            let ip = ipv4ByInterface[name] ?? ""

            var upRate: Double = 0
            var downRate: Double = 0

            if !isFirstSample, elapsed > 0, let prev = lastCounters[name] {
                let upDelta = positiveDelta(previous: prev.outBytes, current: counters.outBytes)
                let downDelta = positiveDelta(previous: prev.inBytes, current: counters.inBytes)

                upRate = Double(upDelta) / elapsed
                downRate = Double(downDelta) / elapsed

                sessionUpTotal += upDelta
                sessionDownTotal += downDelta
            }

            aggregateTotalUp += counters.outBytes
            aggregateTotalDown += counters.inBytes

            // Only include interfaces that have an IPv4 address or have
            // carried any traffic at all -- skip purely idle/unconfigured
            // interfaces to keep the list relevant. Wi-Fi and the built-in
            // Ethernet port stay listed while disconnected, so the submenu
            // can say so. (Thunderbolt ports and adapters are also typed
            // Ethernet but are named "Thunderbolt 1" etc.)
            let hasTraffic = counters.inBytes > 0 || counters.outBytes > 0
            let info = interfaceInfo[name]
            let alwaysListed = info?.kind == .wifi || (info?.kind == .ethernet && info?.name == "Ethernet")
            guard !ip.isEmpty || hasTraffic || alwaysListed else { continue }

            aggregateUpRate += upRate
            aggregateDownRate += downRate

            var ifaceSample = NetworkInterfaceSample()
            ifaceSample.name = name
            ifaceSample.kind = interfaceInfo[name]?.kind ?? Self.kind(forBSDName: name)
            ifaceSample.displayName = interfaceInfo[name]?.name ?? displayName(for: name)
            ifaceSample.upBytesPerSec = upRate
            ifaceSample.downBytesPerSec = downRate
            ifaceSample.ipv4 = ip
            interfaceSamples.append(ifaceSample)
        }

        // 4. Determine the primary interface: first active interface (in
        //    the conventional en0-first ordering) with a non-loopback IPv4.
        if let primary = choosePrimaryInterface(from: interfaceSamples) {
            result.primaryInterface = primary.name
            result.primaryDisplayName = primary.displayName
            result.primaryKind = primary.kind
            result.primaryIP = primary.ipv4
        }

        result.interfaces = interfaceSamples
        result.upBytesPerSec = aggregateUpRate
        result.downBytesPerSec = aggregateDownRate
        result.totalUp = aggregateTotalUp
        result.totalDown = aggregateTotalDown
        result.sessionUp = sessionUpTotal
        result.sessionDown = sessionDownTotal

        // 5. Update state for the next call.
        lastCounters = currentCounters
        lastTimestamp = now
        isFirstSample = false

        return result
    }

    // MARK: - Counter delta helpers

    // Computes current - previous, treating any decrease (counter reset,
    // interface re-attach, etc.) as a zero delta rather than underflowing
    // or producing a huge bogus value.
    private func positiveDelta(previous: UInt64, current: UInt64) -> UInt64 {
        guard current >= previous else { return 0 }
        return current - previous
    }

    private func isLoopback(_ name: String) -> Bool {
        return name.hasPrefix("lo")
    }

    // Label for interfaces System Configuration does not list (tunnels,
    // AWDL). Falls back to the raw BSD name for anything unrecognized.
    private func displayName(for name: String) -> String {
        switch Self.kind(forBSDName: name) {
        case .awdl: return "AWDL"
        case .vpn: return "VPN"
        case .bridge: return "Bridge"
        case .cellular: return "Cellular"
        case .wifi, .ethernet, .other: return name
        }
    }

    private static func kind(forBSDName name: String) -> NetworkInterfaceKind {
        if name.hasPrefix("awdl") || name.hasPrefix("llw") { return .awdl }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") { return .vpn }
        if name.hasPrefix("bridge") { return .bridge }
        if name.hasPrefix("pdp_ip") { return .cellular }
        return .other
    }

    /// Type and localized name ("Wi-Fi", "Ethernet", "Thunderbolt Bridge")
    /// of every interface System Settings knows, keyed by BSD name. `en0`
    /// is Wi-Fi on a MacBook and Ethernet on a Mac Studio, so the BSD name
    /// alone cannot tell them apart.
    private static func readInterfaceInfo() -> [String: (kind: NetworkInterfaceKind, name: String)] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var info: [String: (kind: NetworkInterfaceKind, name: String)] = [:]
        for interface in all {
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let type = SCNetworkInterfaceGetInterfaceType(interface) as String? ?? ""
            let kind: NetworkInterfaceKind
            if type == kSCNetworkInterfaceTypeIEEE80211 as String {
                kind = .wifi
            } else if type == kSCNetworkInterfaceTypeEthernet as String {
                kind = .ethernet
            } else if type == "Bridge" {
                kind = .bridge
            } else if type == kSCNetworkInterfaceTypeWWAN as String {
                kind = .cellular
            } else {
                kind = Self.kind(forBSDName: bsdName)
            }
            let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsdName
            info[bsdName] = (kind, name)
        }
        return info
    }

    // Chooses the primary interface as the first interface (by conventional
    // ordering: en0, en1, ... then everything else alphabetically) that has
    // a non-empty IPv4 address.
    private func choosePrimaryInterface(from interfaces: [NetworkInterfaceSample]) -> NetworkInterfaceSample? {
        let withIP = interfaces.filter { !$0.ipv4.isEmpty }
        guard !withIP.isEmpty else { return nil }

        func sortKey(_ s: NetworkInterfaceSample) -> (Int, String) {
            // Prefer "enN" interfaces, ordered by N, ahead of everything else.
            if s.name.hasPrefix("en"), let n = Int(s.name.dropFirst(2)) {
                return (n, s.name)
            }
            return (Int.max, s.name)
        }

        return withIP.sorted { sortKey($0) < sortKey($1) }.first
    }

    // MARK: - Routing socket interface counters (NET_RT_IFLIST2)

    // Reads 64-bit cumulative in/out byte counters for every interface
    // currently known to the kernel, keyed by interface name. Returns an
    // empty dictionary on any failure (never crashes).
    private func readInterfaceCounters() -> [String: Counters] {
        var counters: [String: Counters] = [:]

        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var neededSize = 0

        // First call: determine required buffer size.
        if sysctl(&mib, u_int(mib.count), nil, &neededSize, nil, 0) != 0 {
            return counters
        }
        guard neededSize > 0 else { return counters }

        var buffer = [UInt8](repeating: 0, count: neededSize)

        let fetchResult = buffer.withUnsafeMutableBytes { rawBuffer -> Int32 in
            var size = neededSize
            return sysctl(&mib, u_int(mib.count), rawBuffer.baseAddress, &size, nil, 0)
        }
        guard fetchResult == 0 else { return counters }

        // We only need three scalar fields out of if_msghdr2 (interface
        // index, in-bytes, out-bytes), read at their known byte offsets.
        // Earlier this loaded the entire ~160-byte if_msghdr2 struct in one
        // shot via loadUnaligned(as: if_msghdr2.self); that reliably
        // produced garbage/collapsed results under -O on this toolchain
        // (Swift 6.1.2) even though it's spec-legal, which smells like a
        // compiler miscompilation on the large-aggregate load path. Reading
        // small scalars individually avoids that path entirely.
        let indexOffset = MemoryLayout<if_msghdr2>.offset(of: \.ifm_index)!
        let dataOffset = MemoryLayout<if_msghdr2>.offset(of: \.ifm_data)!
        let ibytesOffset = dataOffset + MemoryLayout<if_data64>.offset(of: \.ifi_ibytes)!
        let obytesOffset = dataOffset + MemoryLayout<if_data64>.offset(of: \.ifi_obytes)!

        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + 4 <= raw.count {
                // Common rt_msghdr2-style header: ifm_msglen (u_short,
                // offset 0), ifm_version (u_char, offset 2), ifm_type
                // (u_char, offset 3). Offsets aren't guaranteed aligned for
                // these types, so loadUnaligned is required, not load.
                let msgLen = raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
                guard msgLen > 0, offset + Int(msgLen) <= raw.count else { break }

                let msgType = raw.loadUnaligned(fromByteOffset: offset + 3, as: UInt8.self)

                if msgType == UInt8(RTM_IFINFO2), Int(msgLen) >= MemoryLayout<if_msghdr2>.size {
                    let index = raw.loadUnaligned(fromByteOffset: offset + indexOffset, as: UInt16.self)
                    let inBytes = raw.loadUnaligned(fromByteOffset: offset + ibytesOffset, as: UInt64.self)
                    let outBytes = raw.loadUnaligned(fromByteOffset: offset + obytesOffset, as: UInt64.self)

                    // The pointer if_indextoname(3) returns aliases the
                    // buffer we pass it, and is only valid within that
                    // buffer's lifetime/pointer scope -- it must not be
                    // read after `&nameBuf`'s implicit bridging ends. (The
                    // previous version captured the returned pointer and
                    // used it again later to build the dictionary key; that
                    // second read was of already-reclaimed memory, which is
                    // why every interface silently collapsed to a single
                    // empty-string entry under -O.) Building the String
                    // here, still inside the buffer's own scope, is safe.
                    var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    let name: String? = nameBuf.withUnsafeMutableBufferPointer { buf in
                        guard let ptr = if_indextoname(UInt32(index), buf.baseAddress) else { return nil }
                        return String(cString: ptr)
                    }
                    if let name {
                        counters[name] = Counters(inBytes: inBytes, outBytes: outBytes)
                    }
                }

                offset += Int(msgLen)
            }
        }

        return counters
    }

    // MARK: - IPv4 address lookup (getifaddrs)

    // Reads the first IPv4 address for each interface name via getifaddrs,
    // skipping loopback. Frees the linked list before returning. Returns an
    // empty dictionary on any failure.
    private func readIPv4Addresses() -> [String: String] {
        var addresses: [String: String] = [:]

        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
            return addresses
        }
        defer { freeifaddrs(ifaddrPointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            let addr = current.pointee.ifa_addr
            guard let addr = addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: current.pointee.ifa_name)
            guard !isLoopback(name) else { continue }
            // Don't overwrite an address we already captured for this
            // interface (use the first one encountered).
            guard addresses[name] == nil else { continue }

            var addrIn = sockaddr_in()
            memcpy(&addrIn, addr, MemoryLayout<sockaddr_in>.size)

            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var ipAddr = addrIn.sin_addr
            let presentation = inet_ntop(AF_INET, &ipAddr, &buffer, socklen_t(INET_ADDRSTRLEN))
            if let presentation = presentation {
                addresses[name] = String(cString: presentation)
            }
        }

        return addresses
    }
}
