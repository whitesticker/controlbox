import Foundation

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
            var maxLen = 14
            if let data, data.count > 1 {
                let reported = Int(data[1])
                if reported > 0 { maxLen = min(reported, 32) }
            }
            let bytes = Array(trimmed.utf8.prefix(maxLen))
            write(bytes: bytes, offset: 0, featureIndex: featureIndex, request: request, completion: completion)
        }
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
