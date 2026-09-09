import Foundation
import IOKit.hid

/// HID++ 2.0 to one Bolt slot on the receiver vendor pipe. The catalog owns
/// `C548`; readers must not open the dongle themselves.
final class LogiBoltHIDPPLink {
    let receiverID: String
    let slot: Int
    private weak var pipe: LogiBoltPipe?
    var onReport: (([UInt8]) -> Void)?

    var id: String { "\(receiverID)-\(slot)" }

    init(pipe: LogiBoltPipe, slot: Int) {
        self.pipe = pipe
        receiverID = pipe.id
        self.slot = slot
    }

    func write(_ report: [UInt8]) {
        pipe?.write(report)
    }

    func detach() {
        onReport = nil
        pipe = nil
    }
}
