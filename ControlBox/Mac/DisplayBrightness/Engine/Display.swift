import Cocoa
import Foundation
import os.log

class Display: Equatable {
  let identifier: CGDirectDisplayID
  let prefsId: String
  var name: String
  var vendorNumber: UInt32?
  var modelNumber: UInt32?
  var serialNumber: UInt32?
  var smoothBrightnessTransient: Float = 1
  var smoothBrightnessRunning: Bool = false
  var smoothBrightnessSlow: Bool = false

  static func == (lhs: Display, rhs: Display) -> Bool {
    lhs.identifier == rhs.identifier
  }

  var sliderHandler: [Command: SliderHandler] = [:]
  var brightnessSyncSourceValue: Float = 1
  var isVirtual: Bool = false
  var isDummy: Bool = false

  func prefExists(key: PrefKey? = nil, for command: Command? = nil) -> Bool {
    prefs.object(forKey: self.getKey(key: key, for: command)) != nil
  }

  func removePref(key: PrefKey, for command: Command? = nil) {
    prefs.removeObject(forKey: self.getKey(key: key, for: command))
  }

  func savePref<T>(_ value: T, key: PrefKey? = nil, for command: Command? = nil) {
    prefs.set(value, forKey: self.getKey(key: key, for: command))
  }

  func readPrefAsFloat(key: PrefKey? = nil, for command: Command? = nil) -> Float {
    prefs.float(forKey: self.getKey(key: key, for: command))
  }

  func readPrefAsInt(key: PrefKey? = nil, for command: Command? = nil) -> Int {
    prefs.integer(forKey: self.getKey(key: key, for: command))
  }

  func readPrefAsBool(key: PrefKey? = nil, for command: Command? = nil) -> Bool {
    prefs.bool(forKey: self.getKey(key: key, for: command))
  }

  func readPrefAsString(key: PrefKey? = nil, for command: Command? = nil) -> String {
    prefs.string(forKey: self.getKey(key: key, for: command)) ?? ""
  }

  private func getKey(key: PrefKey? = nil, for command: Command? = nil) -> String {
    (key ?? PrefKey.value).rawValue + (command != nil ? String((command ?? Command.none).rawValue) : "") + self.prefsId
  }

  init(_ identifier: CGDirectDisplayID, name: String, vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?, isVirtual: Bool = false, isDummy: Bool = false) {
    self.identifier = identifier
    self.name = name
    self.vendorNumber = vendorNumber
    self.modelNumber = modelNumber
    self.serialNumber = serialNumber
    self.isVirtual = DEBUG_VIRTUAL ? true : isVirtual
    self.isDummy = isDummy
    self.prefsId = "(\(name.filter { !$0.isWhitespace })\(vendorNumber ?? 0)\(modelNumber ?? 0)@\(self.isVirtual ? (self.serialNumber ?? 9999) : identifier))"
    os_log("Display init with prefsIdentifier %{public}@", type: .info, self.prefsId)
    self.smoothBrightnessTransient = self.getBrightness()
    self.brightnessSyncSourceValue = self.getBrightness()
  }

  func calcNewBrightness(isUp: Bool, isSmallIncrement: Bool) -> Float {
    let step: Float = (isUp ? 1 : -1) / (isSmallIncrement ? 64.0 : 16.0)
    let delta = step / 4
    return min(max(0, ceil((self.getBrightness() + delta) / step) * step), 1)
  }

  func stepBrightness(isUp: Bool, isSmallIncrement: Bool) {
    guard !self.readPrefAsBool(key: .unavailableDDC, for: .brightness) else {
      return
    }
    let value = self.calcNewBrightness(isUp: isUp, isSmallIncrement: isSmallIncrement)
    if self.setBrightness(value) {
      OSDUtils.showOsd(displayID: self.identifier, command: .brightness, value: value * 64, maxValue: 64)
      if let slider = self.sliderHandler[.brightness] {
        slider.setValue(value, displayID: self.identifier)
        self.brightnessSyncSourceValue = value
      }
    }
  }

  func setBrightness(_ to: Float = -1, slow: Bool = false) -> Bool {
    if !prefs.bool(forKey: PrefKey.disableSmoothBrightness.rawValue) {
      return self.setSmoothBrightness(to, slow: slow)
    } else {
      return self.setDirectBrightness(to)
    }
  }

  func setSmoothBrightness(_ to: Float = -1, slow: Bool = false) -> Bool {
    guard app.sleepID == 0, app.reconfigureID == 0 else {
      self.savePref(self.smoothBrightnessTransient, for: .brightness)
      self.smoothBrightnessRunning = false
      os_log("Pushing brightness stopped for Display %{public}@ because of sleep or reconfiguration", type: .info, String(self.identifier))
      return false
    }
    if slow {
      self.smoothBrightnessSlow = true
    }
    var stepDivider: Float = 6
    if self.smoothBrightnessSlow {
      stepDivider = 16
    }
    var dontPushAgain = false
    if to != -1 {
      os_log("Pushing brightness towards goal of %{public}@ for Display  %{public}@", type: .info, String(to), String(self.identifier))
      let value = max(min(to, 1), 0)
      self.savePref(value, for: .brightness)
      self.brightnessSyncSourceValue = value
      self.smoothBrightnessSlow = slow
      if self.smoothBrightnessRunning {
        return true
      }
    }
    let brightness = self.readPrefAsFloat(for: .brightness)
    if brightness != self.smoothBrightnessTransient {
      if abs(brightness - self.smoothBrightnessTransient) < 0.01 {
        self.smoothBrightnessTransient = brightness
        os_log("Pushing brightness finished for Display  %{public}@", type: .info, String(self.identifier))
        dontPushAgain = true
        self.smoothBrightnessRunning = false
      } else if brightness > self.smoothBrightnessTransient {
        self.smoothBrightnessTransient += max((brightness - self.smoothBrightnessTransient) / stepDivider, 1 / 100)
      } else {
        self.smoothBrightnessTransient += min((brightness - self.smoothBrightnessTransient) / stepDivider, 1 / 100)
      }
      _ = self.setDirectBrightness(self.smoothBrightnessTransient, transient: true)
      if !dontPushAgain {
        self.smoothBrightnessRunning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
          _ = self.setSmoothBrightness()
        }
      }
    } else {
      os_log("No more need to push brightness for Display  %{public}@ (setting one final time)", type: .info, String(self.identifier))
      _ = self.setDirectBrightness(self.smoothBrightnessTransient, transient: true)
      self.smoothBrightnessRunning = false
    }
    return true
  }

  func setDirectBrightness(_: Float, transient _: Bool = false) -> Bool {
    false
  }

  func getBrightness() -> Float {
    if self.prefExists(for: .brightness) {
      return self.readPrefAsFloat(for: .brightness)
    } else {
      return 1
    }
  }

  func refreshBrightness() -> Float {
    0
  }

  func isBuiltIn() -> Bool {
    if CGDisplayIsBuiltin(self.identifier) != 0 {
      return true
    } else {
      return false
    }
  }
}
