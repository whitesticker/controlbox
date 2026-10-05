import Foundation

/// One attached screen as the Displays pane and brightness extra show it.
public struct AttachedDisplay: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var brightness: Double
    public var contrast: Double
    public var volume: Double
    public var canAdjustBrightness: Bool
    public var canAdjustContrast: Bool
    public var canAdjustVolume: Bool
    public var isBuiltIn: Bool
    public var isDummy: Bool

    public var canAdjust: Bool { canAdjustBrightness }

    public init(
        id: String,
        name: String,
        detail: String,
        brightness: Double,
        contrast: Double = 1,
        volume: Double = 0,
        canAdjustBrightness: Bool,
        canAdjustContrast: Bool = false,
        canAdjustVolume: Bool = false,
        isBuiltIn: Bool,
        isDummy: Bool = false
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.brightness = brightness
        self.contrast = contrast
        self.volume = volume
        self.canAdjustBrightness = canAdjustBrightness
        self.canAdjustContrast = canAdjustContrast
        self.canAdjustVolume = canAdjustVolume
        self.isBuiltIn = isBuiltIn
        self.isDummy = isDummy
    }
}
