import IRemoteControl
import Observation
import SwiftUI

@Observable
@MainActor
final class DisplayCatalog {
    var displays: [AttachedDisplay] = []
    private var writeWork: [String: DispatchWorkItem] = [:]

    func refresh() {
        displays = DisplayBrightness.connectedDisplays()
    }

    func setBrightness(_ value: Double, id: String) {
        setValue(value, id: id, field: "brightness") { DisplayBrightness.setBrightness($0, id: $1) }
    }

    func setContrast(_ value: Double, id: String) {
        setValue(value, id: id, field: "contrast") { DisplayBrightness.setContrast($0, id: $1) }
    }

    private func setValue(
        _ value: Double,
        id: String,
        field: String,
        write: @escaping (Double, String) -> Void
    ) {
        if let index = displays.firstIndex(where: { $0.id == id }) {
            if field == "brightness" {
                displays[index].brightness = value
            } else {
                displays[index].contrast = value
            }
        }
        let token = "\(id):\(field)"
        writeWork[token]?.cancel()
        let work = DispatchWorkItem {
            write(value, id)
        }
        writeWork[token] = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05, execute: work)
    }
}
