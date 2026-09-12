import Foundation

/// Optional hardware a gamepad may or may not expose.
/// Defaults are all off so a decoded generic record does not invent DualSense extras.
public struct GamepadCapabilities: Codable, Equatable, Sendable {
    public var touchpad: Bool
    public var motion: Bool
    public var haptics: Bool
    public var battery: Bool

    public init(
        touchpad: Bool = false,
        motion: Bool = false,
        haptics: Bool = false,
        battery: Bool = false
    ) {
        self.touchpad = touchpad
        self.motion = motion
        self.haptics = haptics
        self.battery = battery
    }

    public static let none = GamepadCapabilities()

    public static let dualSense = GamepadCapabilities(
        touchpad: true,
        motion: true,
        haptics: true,
        battery: true
    )
}
