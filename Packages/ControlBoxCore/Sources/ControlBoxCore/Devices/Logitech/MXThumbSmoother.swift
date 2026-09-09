import Foundation

/// OpenLogi’s finite cubic-smoothstep interpolator (100 ms, ~8 ms frames).
/// Input is diverted HID++ increment counts. `MXWheelActionEngine` maps each
/// frame onto the live thumb mode (scroll, tabs, volume, desktops, …).
final class MXThumbSmoother {
    static let animationDuration: TimeInterval = 0.100
    static let frameInterval: TimeInterval = 0.008

    enum Phase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
        case cancelled = 8
    }

    struct Frame {
        var delta: Double
        var phase: Phase
    }

    private struct Segment {
        var from = 0.0
        var target = 0.0
        var startedAt = 0.0

        func position(at time: TimeInterval) -> Double {
            let elapsed = max(time - startedAt, 0)
            let progress = min(elapsed / MXThumbSmoother.animationDuration, 1)
            let eased = progress * progress * (3 - 2 * progress)
            return from + (target - from) * eased
        }

        func isComplete(at time: TimeInterval) -> Bool {
            time >= startedAt + MXThumbSmoother.animationDuration
        }
    }

    private enum Update {
        case active(Double)
        case finished(Double)

        var isFinished: Bool {
            if case .finished = self { return true }
            return false
        }
    }

    private struct Motion {
        var segment = Segment()
        var emitted = 0.0
        var nextFrame = 0.0

        mutating func delta(to position: Double) -> Double {
            let delta = position - emitted
            emitted = position
            return delta
        }

        mutating func advance(at time: TimeInterval) -> Update {
            let complete = segment.isComplete(at: time)
            let position = segment.position(at: time)
            let delta = self.delta(to: position)
            if complete {
                return .finished(delta)
            }
            while nextFrame <= time {
                nextFrame += MXThumbSmoother.frameInterval
            }
            nextFrame = min(nextFrame, segment.startedAt + MXThumbSmoother.animationDuration)
            return .active(delta)
        }
    }

    private enum Output {
        case idle
        case active
    }

    private var motion: Motion?
    private var output = Output.idle

    var isActive: Bool { motion != nil }

    func impulse(_ delta: Double, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [Frame] {
        guard delta.isFinite, delta != 0 else { return [] }
        var frames: [Frame] = []
        if var completed = motion, completed.segment.isComplete(at: time) {
            motion = nil
            emit(completed.advance(at: time), into: &frames)
        }
        if var current = motion {
            let position = current.segment.position(at: time)
            let target = current.segment.target + delta
            let step = current.delta(to: position)
            if target == position {
                motion = nil
                emit(.finished(step), into: &frames)
                return frames
            }
            current.segment = Segment(from: position, target: target, startedAt: time)
            current.nextFrame = time + Self.frameInterval
            motion = current
            emit(.active(step), into: &frames)
        } else {
            motion = Motion(
                segment: Segment(from: 0, target: delta, startedAt: time),
                emitted: 0,
                nextFrame: time + Self.frameInterval
            )
        }
        return frames
    }

    func advance(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [Frame] {
        guard var current = motion, current.nextFrame <= time else { return [] }
        let update = current.advance(at: time)
        if update.isFinished {
            motion = nil
        } else {
            motion = current
        }
        var frames: [Frame] = []
        emit(update, into: &frames)
        return frames
    }

    func cancel() -> [Frame] {
        motion = nil
        guard output == .active else { return [] }
        output = .idle
        return [Frame(delta: 0, phase: .cancelled)]
    }

    func reset() {
        motion = nil
        output = .idle
    }

    private func emit(_ update: Update, into frames: inout [Frame]) {
        switch update {
        case .finished(let delta):
            if motion == nil {
                finish(delta, into: &frames)
            } else {
                progress(delta, into: &frames)
            }
        case .active(let delta):
            progress(delta, into: &frames)
        }
    }

    private func progress(_ delta: Double, into frames: inout [Frame]) {
        guard delta != 0 else { return }
        switch output {
        case .idle:
            output = .active
            frames.append(Frame(delta: delta, phase: .began))
        case .active:
            frames.append(Frame(delta: delta, phase: .changed))
        }
    }

    private func finish(_ delta: Double, into frames: inout [Frame]) {
        switch output {
        case .idle where delta != 0:
            frames.append(Frame(delta: delta, phase: .began))
            frames.append(Frame(delta: 0, phase: .ended))
        case .active:
            frames.append(Frame(delta: delta, phase: .ended))
        case .idle:
            break
        }
        output = .idle
    }
}
