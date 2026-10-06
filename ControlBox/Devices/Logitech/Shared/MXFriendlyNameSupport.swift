import Foundation

/// Where a committed device name is on its way to the device's own storage.
enum FriendlyNameWrite: Equatable {
    case waiting
    case saving
    case saved
    case failed
}

/// HID++ `0x0007` Device Friendly Name. Stored on the mouse or keyboard.
/// `0x0005` is the factory model name and is read-only.
enum MXFriendlyNameHIDPP {
    static let featureID: UInt16 = 0x0007

    typealias Request = (
        _ featureIndex: UInt8,
        _ function: UInt8,
        _ params: [UInt8],
        _ completion: @escaping (Data?) -> Void
    ) -> Void

    static func set(
        name: String,
        featureIndex: UInt8,
        request: @escaping Request,
        completion: @escaping (Bool) -> Void
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            request(featureIndex, 4, []) { data in
                completion(data != nil)
            }
            return
        }
        request(featureIndex, 0, []) { data in
            let maxLen = maxLength(from: data) ?? fallbackMaxLength
            let bytes = Array(clipped(trimmed, maxBytes: maxLen).utf8)
            write(bytes: bytes, offset: 0, featureIndex: featureIndex, request: request, completion: completion)
        }
    }

    static let fallbackMaxLength = 14

    /// `getFriendlyNameLen` byte 1: the longest name the device stores, in UTF-8 bytes.
    static func readMaxLength(
        featureIndex: UInt8,
        request: @escaping Request,
        completion: @escaping (Int?) -> Void
    ) {
        request(featureIndex, 0, []) { data in
            completion(maxLength(from: data))
        }
    }

    /// Longest prefix of whole characters that fits in `maxBytes` UTF-8 bytes.
    static func clipped(_ name: String, maxBytes: Int) -> String {
        var result = ""
        var used = 0
        for character in name {
            let size = character.utf8.count
            if used + size > maxBytes { break }
            result.append(character)
            used += size
        }
        return result
    }

    private static func maxLength(from data: Data?) -> Int? {
        guard let data, data.count > 1 else { return nil }
        let reported = Int(data[data.startIndex + 1])
        return reported > 0 ? min(reported, 32) : nil
    }

    private static func write(
        bytes: [UInt8],
        offset: Int,
        featureIndex: UInt8,
        request: @escaping Request,
        completion: @escaping (Bool) -> Void
    ) {
        if bytes.isEmpty {
            completion(true)
            return
        }
        let take = min(15, bytes.count)
        var params = [UInt8(offset)]
        params.append(contentsOf: bytes.prefix(take))
        request(featureIndex, 3, params) { data in
            guard data != nil else {
                completion(false)
                return
            }
            let rest = Array(bytes.dropFirst(take))
            if rest.isEmpty {
                completion(true)
                return
            }
            write(
                bytes: rest,
                offset: offset + take,
                featureIndex: featureIndex,
                request: request,
                completion: completion
            )
        }
    }
}
