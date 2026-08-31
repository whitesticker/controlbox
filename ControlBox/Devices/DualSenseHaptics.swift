import CoreHaptics
import Foundation
import GameController

@MainActor
final class DualSenseHaptics {
    private var engine: CHHapticEngine?
    private var attached: GCController?
    private var ready = false

    func attach(_ controller: GCController) {
        if attached === controller, engine != nil { return }
        detach()
        attached = controller
        guard let haptics = controller.haptics else { return }

        let preferred: [GCHapticsLocality] = [.handles, .default, .all]
        let locality = preferred.first { haptics.supportedLocalities.contains($0) }
            ?? haptics.supportedLocalities.first
        guard let locality, let created = haptics.createEngine(withLocality: locality) else { return }

        engine = created
        created.playsHapticsOnly = true
        created.stoppedHandler = { [weak self] _ in
            Task { @MainActor in
                self?.ready = false
            }
        }
        created.resetHandler = { [weak self] in
            Task { @MainActor in
                self?.start()
            }
        }
        start()
    }

    func detach() {
        ready = false
        engine?.stop(completionHandler: nil)
        engine = nil
        attached = nil
    }

    func pulse() {
        if !ready {
            start()
        }
        guard ready, let engine else { return }

        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.72)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.45)
        let rumble = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensity, sharpness],
            relativeTime: 0,
            duration: 0.08
        )
        let tap = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85)
            ],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [tap, rumble], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            start()
        }
    }

    private func start() {
        guard let engine else { return }
        do {
            try engine.start()
            ready = true
        } catch {
            ready = false
        }
    }
}
