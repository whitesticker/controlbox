import Foundation

/// One Easy-Switch channel stored on an MX mouse or keyboard.
/// Channel numbers are 1-based. HID++ host indexes are 0-based.
struct MXEasySwitchHost: Equatable, Identifiable, Sendable {
    var index: Int
    var isPaired: Bool
    var isCurrent: Bool
    var name: String
    var bus: MXEasySwitchBus
    var isPending: Bool = false

    var id: Int { index }
    var channelNumber: Int { index + 1 }

    var title: String { "Channel \(channelNumber)" }

    static func pending(index: Int) -> MXEasySwitchHost {
        MXEasySwitchHost(
            index: index,
            isPaired: false,
            isCurrent: false,
            name: "",
            bus: .unknown,
            isPending: true
        )
    }

    var primary: String {
        if isPending { return "Pending" }
        if isCurrent, name.isEmpty { return "This Mac" }
        if !name.isEmpty { return name }
        if isPaired { return "Paired" }
        return "Empty"
    }

    var secondary: String? {
        guard isPaired, bus != .unknown else { return nil }
        return bus.title
    }
}

enum MXEasySwitchBus: Equatable, Sendable {
    case unknown
    case unifying
    case usb
    case bluetooth
    case bolt

    var title: String {
        switch self {
        case .unknown: return ""
        case .unifying: return "Unifying"
        case .usb: return "USB"
        case .bluetooth: return "Bluetooth"
        case .bolt: return "Logi Bolt"
        }
    }

    init(raw: UInt8) {
        switch raw {
        case 1: self = .unifying
        case 2: self = .usb
        case 3, 4: self = .bluetooth
        case 5: self = .bolt
        default: self = .unknown
        }
    }
}

/// HID++ `0x1814` CHANGE_HOST and `0x1815` HOSTS_INFO.
/// Verified 2026-09-07 on MX Mechanical Mini over Bolt: three channels,
/// names via function 3 chunks, current host from function 0.
enum MXEasySwitchHIDPP {
    static let changeHostFeature: UInt16 = 0x1814
    static let hostsInfoFeature: UInt16 = 0x1815

    typealias Request = (
        _ featureIndex: UInt8,
        _ function: UInt8,
        _ params: [UInt8],
        _ completion: @escaping (Data?) -> Void
    ) -> Void

    static func load(
        hostsInfoIndex: UInt8?,
        changeHostIndex: UInt8?,
        request: @escaping Request,
        completion: @escaping ([MXEasySwitchHost]) -> Void
    ) {
        guard hostsInfoIndex != nil || changeHostIndex != nil else {
            completion([])
            return
        }
        var hostCount = 0
        var currentHost = -1

        func finish(_ hosts: [MXEasySwitchHost]) {
            completion(hosts)
        }

        func readChangeHostThenInfo() {
            guard let changeHostIndex else {
                readHostsInfo()
                return
            }
            request(changeHostIndex, 0, []) { data in
                if let data, data.count >= 2 {
                    hostCount = Int(data[0])
                    currentHost = Int(data[1])
                }
                readHostsInfo()
            }
        }

        func readHostsInfo() {
            guard let hostsInfoIndex else {
                readHost(0, accumulated: [])
                return
            }
            request(hostsInfoIndex, 0, []) { data in
                if let data, data.count >= 4 {
                    hostCount = Int(data[2])
                    currentHost = Int(data[3])
                }
                readHost(0, accumulated: [])
            }
        }

        func readHost(_ index: Int, accumulated: [MXEasySwitchHost]) {
            let count = min(max(hostCount, 0), 6)
            if currentHost == 0xFF { currentHost = -1 }
            if count <= 0 || index >= count {
                finish(accumulated)
                return
            }
            guard let hostsInfoIndex else {
                var next = accumulated
                next.append(
                    MXEasySwitchHost(
                        index: index,
                        isPaired: true,
                        isCurrent: index == currentHost,
                        name: "",
                        bus: .unknown
                    )
                )
                readHost(index + 1, accumulated: next)
                return
            }
            request(hostsInfoIndex, 1, [UInt8(index)]) { data in
                var paired = false
                var bus = MXEasySwitchBus.unknown
                var nameLen = 0
                if let data {
                    if data.count > 1 { paired = data[1] == 1 }
                    if data.count > 2 { bus = MXEasySwitchBus(raw: data[2]) }
                    if data.count > 4 { nameLen = Int(data[4]) }
                }
                readName(host: index, offset: 0, remaining: nameLen, assembled: "") { name in
                    var next = accumulated
                    next.append(
                        MXEasySwitchHost(
                            index: index,
                            isPaired: paired,
                            isCurrent: index == currentHost,
                            name: name,
                            bus: bus
                        )
                    )
                    readHost(index + 1, accumulated: next)
                }
            }
        }

        func readName(host: Int, offset: Int, remaining: Int, assembled: String, done: @escaping (String) -> Void) {
            guard let hostsInfoIndex else {
                done(assembled)
                return
            }
            if remaining <= 0 {
                done(assembled.trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
            request(hostsInfoIndex, 3, [UInt8(host), UInt8(offset)]) { data in
                guard let data else {
                    done(assembled.trimmingCharacters(in: .whitespacesAndNewlines))
                    return
                }
                let piece = namePiece(from: data, remaining: remaining)
                let consumed = min(remaining, 14)
                readName(
                    host: host,
                    offset: offset + consumed,
                    remaining: remaining - consumed,
                    assembled: assembled + piece,
                    done: done
                )
            }
        }

        readChangeHostThenInfo()
    }

    static func namePiece(from payload: Data, remaining: Int) -> String {
        guard payload.count >= 3, remaining > 0 else { return "" }
        let take = min(remaining, 14, payload.count - 2)
        var bytes = Array(payload.dropFirst(2).prefix(take))
        while bytes.last == 0 {
            bytes.removeLast()
        }
        if let text = String(bytes: bytes, encoding: .utf8), !text.isEmpty {
            return text
        }
        return String(bytes.compactMap { byte -> Character? in
            guard byte >= 32, byte < 127, let scalar = UnicodeScalar(UInt32(byte)) else { return nil }
            return Character(scalar)
        })
    }
}
