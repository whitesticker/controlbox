import SwiftUI

/// Deterministic fake telemetry. One stream per metric; `next()` produces one
/// bucket (avg/min/max) per series, so the same code fills a 5 min, 1 h, or
/// 24 h range and keeps appending while Live is on.
struct MockStream {
    private var rng: SplitMix64
    private let metric: Metric
    private let scenario: Scenario
    private let spread: Bool

    private var load = 0.15
    private var gpu = 0.08
    private var burst = 0.0
    private var memory = 0.55
    private var down = 40_000.0
    private var up = 12_000.0
    private var temps: [Double] = [40, 37, 52, 35, 31]

    init(metric: Metric, scenario: Scenario, seed: UInt64, spread: Bool) {
        rng = SplitMix64(seed: seed &+ UInt64(Metric.allCases.firstIndex(of: metric) ?? 0) &* 7919)
        self.metric = metric
        self.scenario = scenario
        self.spread = spread
        load = baseLoad
    }

    static func seriesDefinitions(_ metric: Metric) -> [(id: String, name: String, color: Color)] {
        switch metric {
        case .cpu: return [("cpu", "CPU", .blue)]
        case .gpu: return [("gpu", "GPU", .purple)]
        case .memory: return [("pressure", "Pressure", .green)]
        case .network: return [("down", "Download", .blue), ("up", "Upload", .red)]
        case .disk: return [("read", "Read", .orange), ("write", "Write", .teal)]
        case .temperatures:
            return [
                ("cpu", "CPU", .orange), ("gpu", "GPU", .purple), ("soc", "SoC", .red),
                ("power", "Power", .yellow), ("enclosure", "Enclosure", .teal),
            ]
        case .fans: return [("fan0", "Fan 0", .cyan), ("fan1", "Fan 1", .indigo)]
        }
    }

    private var baseLoad: Double {
        switch scenario {
        case .calm: return 0.1
        case .busy: return 0.55
        case .spiky: return 0.14
        }
    }

    private var burstChance: Double {
        switch scenario {
        case .calm: return 0.02
        case .busy: return 0.05
        case .spiky: return 0.12
        }
    }

    mutating func next() -> [(avg: Double, min: Double, max: Double)] {
        stepLoad()
        switch metric {
        case .cpu:
            return [band(load, jitter: 0.25, floor: 0, ceil: 1)]
        case .gpu:
            gpu = clamp(gpu * 0.9 + (load * 0.5 + rng.unit() * 0.05) * 0.1, 0, 1)
            return [band(gpu, jitter: 0.3, floor: 0, ceil: 1)]
        case .memory:
            memory = clamp(memory + rng.signed() * 0.004 + (load - baseLoad) * 0.01, 0.3, 0.95)
            let pressure = clamp((memory - 0.4) * 0.8 + load * 0.15, 0.02, 1)
            return [band(pressure, jitter: 0.1, floor: 0, ceil: 1)]
        case .network:
            down = drift(down, base: scenario == .busy ? 400_000 : 40_000)
            up = drift(up, base: scenario == .busy ? 120_000 : 12_000)
            let spike = rng.unit() < burstChance ? rng.unit() * 9_000_000 : 0
            return [spiky(down + spike), spiky(up + spike * 0.15)]
        case .disk:
            let read = rng.unit() < burstChance * 2 ? rng.unit() * 40_000_000 : rng.unit() * 120_000
            let write = rng.unit() < burstChance * 1.5 ? rng.unit() * 25_000_000 : rng.unit() * 60_000
            return [spiky(read), spiky(write)]
        case .temperatures:
            let targets = [38 + load * 45, 35 + gpu * 30 + load * 8, 50 + load * 30, 33 + load * 8, 31 + load * 3]
            for i in temps.indices {
                temps[i] += (targets[i] - temps[i]) * 0.15 + rng.signed() * 0.4
            }
            return temps.map { band($0, jitter: 0.04, floor: 15, ceil: 110) }
        case .fans:
            let cpuTemp = 38 + load * 45
            let rpm = 1000 + max(0, cpuTemp - 48) * 90
            return [band(rpm + rng.signed() * 8, jitter: 0.03, floor: 0, ceil: 6000),
                    band(rpm * 0.99 + rng.signed() * 8, jitter: 0.03, floor: 0, ceil: 6000)]
        }
    }

    private mutating func stepLoad() {
        if rng.unit() < burstChance { burst = 0.3 + rng.unit() * 0.5 }
        burst *= 0.8
        load = clamp(load + (baseLoad - load) * 0.1 + rng.signed() * 0.03 + burst * 0.4, 0.01, 1)
    }

    private mutating func drift(_ value: Double, base: Double) -> Double {
        max(500, value + (base - value) * 0.2 + rng.signed() * base * 0.4)
    }

    private mutating func band(_ v: Double, jitter: Double, floor: Double, ceil: Double) -> (avg: Double, min: Double, max: Double) {
        guard spread else { return (v, v, v) }
        let lo = clamp(v * (1 - rng.unit() * jitter), floor, ceil)
        let hi = clamp(v * (1 + rng.unit() * jitter * 1.5), floor, ceil)
        return (v, lo, hi)
    }

    private mutating func spiky(_ v: Double) -> (avg: Double, min: Double, max: Double) {
        guard spread else { return (v, v, v) }
        return (v, v * (0.3 + rng.unit() * 0.4), v * (1.5 + rng.unit() * 3))
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        Swift.min(Swift.max(v, lo), hi)
    }
}

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func signed() -> Double {
        unit() * 2 - 1
    }
}
