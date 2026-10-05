import Cocoa
import CoreGraphics
import os.log

class DisplayManager {
  static let shared = DisplayManager()

  var displays: [Display] = []
  var audioControlTargetDisplays: [OtherDisplay] = []
  let globalDDCQueue = DispatchQueue(label: "Global DDC queue")

  func configureDisplays() {
    self.clearDisplays()
    var onlineDisplayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
    var displayCount: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &onlineDisplayIDs, &displayCount) == .success else {
      os_log("Unable to get display list.", type: .info)
      return
    }
    for onlineDisplayID in onlineDisplayIDs where onlineDisplayID != 0 {
      let name = DisplayManager.getDisplayNameByID(displayID: onlineDisplayID)
      let id = onlineDisplayID
      let vendorNumber = CGDisplayVendorNumber(onlineDisplayID)
      let modelNumber = CGDisplayModelNumber(onlineDisplayID)
      let serialNumber = CGDisplaySerialNumber(onlineDisplayID)
      let isDummy: Bool = DisplayManager.isDummy(displayID: onlineDisplayID)
      let isVirtual: Bool = DisplayManager.isVirtual(displayID: onlineDisplayID)
      if !DEBUG_SW, DisplayManager.isAppleDisplay(displayID: onlineDisplayID) { // MARK: (point of interest for testing)

        let appleDisplay = AppleDisplay(id, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber, isVirtual: isVirtual, isDummy: isDummy)
        os_log("Apple display found - %{public}@", type: .info, "ID: \(appleDisplay.identifier), Name: \(appleDisplay.name) (Vendor: \(appleDisplay.vendorNumber ?? 0), Model: \(appleDisplay.modelNumber ?? 0))")
        self.addDisplay(display: appleDisplay)
      } else {
        let otherDisplay = OtherDisplay(id, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber, isVirtual: isVirtual, isDummy: isDummy)
        os_log("Other display found - %{public}@", type: .info, "ID: \(otherDisplay.identifier), Name: \(otherDisplay.name) (Vendor: \(otherDisplay.vendorNumber ?? 0), Model: \(otherDisplay.modelNumber ?? 0))")
        self.addDisplay(display: otherDisplay)
      }
    }
  }

  func setupOtherDisplays(firstrun: Bool = false) {
    for otherDisplay in self.getOtherDisplays() {
      for command in [Command.audioSpeakerVolume, Command.contrast] where !otherDisplay.readPrefAsBool(key: .unavailableDDC, for: command) && !otherDisplay.isSw() {
        otherDisplay.setupCurrentAndMaxValues(command: command, firstrun: firstrun)
      }
      if (!otherDisplay.isSw() && !otherDisplay.readPrefAsBool(key: .unavailableDDC, for: .brightness)) || otherDisplay.isSw() {
        otherDisplay.setupCurrentAndMaxValues(command: .brightness, firstrun: firstrun)
        otherDisplay.brightnessSyncSourceValue = otherDisplay.readPrefAsFloat(for: .brightness)
      }
    }
  }

  func restoreOtherDisplays() {
    for otherDisplay in self.getDdcCapableDisplays() {
      for command in [Command.contrast, Command.brightness] where !otherDisplay.readPrefAsBool(key: .unavailableDDC, for: command) {
        otherDisplay.restoreDDCSettingsToDisplay(command: command)
      }
    }
  }

  func normalizedName(_ name: String) -> String {
    var normalizedName = name.replacingOccurrences(of: "(", with: "")
    normalizedName = normalizedName.replacingOccurrences(of: ")", with: "")
    normalizedName = normalizedName.replacingOccurrences(of: " ", with: "")
    for i in 0 ... 9 {
      normalizedName = normalizedName.replacingOccurrences(of: String(i), with: "")
    }
    return normalizedName
  }

  func updateAudioControlTargetDisplays(deviceName: String) -> Int {
    self.audioControlTargetDisplays.removeAll()
    os_log("Detecting displays for audio control via audio device name matching...", type: .info)
    var numOfAddedDisplays = 0
    for ddcCapableDisplay in self.getDdcCapableDisplays() {
      var displayAudioDeviceName = ddcCapableDisplay.readPrefAsString(key: .audioDeviceNameOverride)
      if displayAudioDeviceName == "" {
        displayAudioDeviceName = DisplayManager.getDisplayRawNameByID(displayID: ddcCapableDisplay.identifier)
      }
      if self.normalizedName(displayAudioDeviceName) == self.normalizedName(deviceName) {
        self.audioControlTargetDisplays.append(ddcCapableDisplay)
        numOfAddedDisplays += 1
        os_log("Added display for audio control - %{public}@", type: .info, ddcCapableDisplay.name)
      }
    }
    return numOfAddedDisplays
  }

  func getOtherDisplays() -> [OtherDisplay] {
    self.displays.compactMap { $0 as? OtherDisplay }
  }

  func sortDisplays() {
    // Opsiyonel: sıralamadan önce log al
    let before = self.displays.map(\.name)
    os_log("Displays before sorting: %{public}@", before)

    // In‑place sıralama
    self.displays.sort { lhs, rhs in
      lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    // Opsiyonel: sıralamadan sonra log al
    let after = self.displays.map(\.name)
    os_log("Displays after sorting: %{public}@", after)
  }

  func sortDisplaysByFriendlyName() -> [Display] {
    self.displays.sorted { lhs, rhs in
      let lhsTitle = lhs.readPrefAsString(key: .friendlyName).isEmpty
        ? lhs.name
        : lhs.readPrefAsString(key: .friendlyName)
      let rhsTitle = rhs.readPrefAsString(key: .friendlyName).isEmpty
        ? rhs.name
        : rhs.readPrefAsString(key: .friendlyName)
      return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedDescending
    }
  }

  /// displays dizisini sıralar ve döner
  func getAllDisplays() -> [Display] {
    self.displays
  }

  func getDdcCapableDisplays() -> [OtherDisplay] {
    self.displays.compactMap { display -> OtherDisplay? in
      if let otherDisplay = display as? OtherDisplay, !otherDisplay.isSw() {
        return otherDisplay
      } else {
        return nil
      }
    }
  }

  func getAppleDisplays() -> [AppleDisplay] {
    self.displays.compactMap { $0 as? AppleDisplay }
  }

  func getBuiltInDisplay() -> Display? {
    self.displays.first { CGDisplayIsBuiltin($0.identifier) != 0 }
  }

  func getCurrentDisplay(byFocus: Bool = false) -> Display? {
    if byFocus {
      guard let mainDisplayID = NSScreen.main?.displayID else {
        return nil
      }
      return self.displays.first { $0.identifier == mainDisplayID }
    } else {
      let mouseLocation = NSEvent.mouseLocation
      let screens = NSScreen.screens
      if let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }) {
        return self.displays.first { $0.identifier == screenWithMouse.displayID }
      }
      return nil
    }
  }

  func addDisplay(display: Display) {
    self.displays.append(display)
  }

  func clearDisplays() {
    self.displays = []
  }

  func addDisplayCounterSuffixes() {
    var nameDisplays: [String: [Display]] = [:]
    for display in self.displays {
      if nameDisplays[display.name] != nil {
        nameDisplays[display.name]?.append(display)
      } else {
        nameDisplays[display.name] = [display]
      }
    }
    for nameDisplayKey in nameDisplays.keys where nameDisplays[nameDisplayKey]?.count ?? 0 > 1 {
      for i in 0 ... (nameDisplays[nameDisplayKey]?.count ?? 1) - 1 {
        if let display = nameDisplays[nameDisplayKey]?[i] {
          display.name = "" + display.name + " (" + String(i + 1) + ")"
        }
      }
    }
  }

  func updateArm64AVServices() {
    if Arm64DDC.isArm64 {
      os_log("arm64 AVService update requested", type: .info)
      var displayIDs: [CGDirectDisplayID] = []
      for otherDisplay in self.getOtherDisplays() {
        displayIDs.append(otherDisplay.identifier)
      }
      for serviceMatch in Arm64DDC.getServiceMatches(displayIDs: displayIDs) {
        for otherDisplay in self.getOtherDisplays() where otherDisplay.identifier == serviceMatch.displayID && serviceMatch.service != nil {
          otherDisplay.arm64avService = serviceMatch.service
          os_log("Display service match successful for display %{public}@", type: .info, String(serviceMatch.displayID))
          if serviceMatch.discouraged {
            os_log("Display %{public}@ is flagged as discouraged by Arm64DDC.", type: .info, String(serviceMatch.displayID))
            otherDisplay.isDiscouraged = true
          } else if serviceMatch.dummy {
            os_log("Display %{public}@ is flagged as dummy by Arm64DDC.", type: .info, String(serviceMatch.displayID))
            otherDisplay.isDiscouraged = true
            otherDisplay.isDummy = true
          } else {
            otherDisplay.arm64ddc = DEBUG_SW ? false : true // MARK: (point of interest when testing)
          }
        }
      }
      os_log("AVService update done", type: .info)
    }
  }

  func getAffectedDisplays(isBrightness: Bool = false, isVolume: Bool = false) -> [Display]? {
    var affectedDisplays: [Display]
    let allDisplays = self.getAllDisplays()
    var currentDisplay: Display?
    if isBrightness {
      if prefs.integer(forKey: PrefKey.multiKeyboardBrightness.rawValue) == MultiKeyboardBrightness.allScreens.rawValue {
        affectedDisplays = allDisplays
        return affectedDisplays
      }
      currentDisplay = self.getCurrentDisplay(byFocus: prefs.integer(forKey: PrefKey.multiKeyboardBrightness.rawValue) == MultiKeyboardBrightness.focusInsteadOfMouse.rawValue)
    }
    if isVolume {
      if prefs.integer(forKey: PrefKey.multiKeyboardVolume.rawValue) == MultiKeyboardVolume.allScreens.rawValue {
        affectedDisplays = allDisplays
        return affectedDisplays
      } else if prefs.integer(forKey: PrefKey.multiKeyboardVolume.rawValue) == MultiKeyboardVolume.audioDeviceNameMatching.rawValue {
        return self.audioControlTargetDisplays
      }
      currentDisplay = self.getCurrentDisplay(byFocus: false)
    }
    if let currentDisplay = currentDisplay {
      affectedDisplays = [currentDisplay]
      if CGDisplayIsInHWMirrorSet(currentDisplay.identifier) != 0 || CGDisplayIsInMirrorSet(currentDisplay.identifier) != 0, CGDisplayMirrorsDisplay(currentDisplay.identifier) == 0 {
        for display in allDisplays where CGDisplayMirrorsDisplay(display.identifier) == currentDisplay.identifier {
          affectedDisplays.append(display)
        }
      }
    } else {
      affectedDisplays = []
    }
    return affectedDisplays
  }

  static func isDummy(displayID: CGDirectDisplayID) -> Bool {
    let vendorNumber = CGDisplayVendorNumber(displayID)
    let rawName = DisplayManager.getDisplayRawNameByID(displayID: displayID)
    if rawName.lowercased().contains("dummy") || (self.isVirtual(displayID: displayID) && vendorNumber == UInt32(0xF0F0)) {
      os_log("NOTE: Display is a dummy!", type: .info)
      return true
    }
    return false
  }

  static func isVirtual(displayID: CGDirectDisplayID) -> Bool {
    var isVirtual = false
    if !DEBUG_MACOS10, #available(macOS 11.0, *) {
      if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?) {
        let isVirtualDevice = dictionary["kCGDisplayIsVirtualDevice"] as? Bool
        let displayIsAirplay = dictionary["kCGDisplayIsAirPlay"] as? Bool
        if isVirtualDevice ?? displayIsAirplay ?? false {
          isVirtual = true
        }
      }
    }
    return isVirtual
  }

  static func resolveEffectiveDisplayID(_ displayID: CGDirectDisplayID) -> CGDirectDisplayID {
    var realDisplayID = displayID
    if CGDisplayIsInHWMirrorSet(displayID) != 0 || CGDisplayIsInMirrorSet(displayID) != 0 {
      let mirroredDisplayID = CGDisplayMirrorsDisplay(displayID)
      if mirroredDisplayID != 0 {
        realDisplayID = mirroredDisplayID
      }
    }
    return realDisplayID
  }

  static func isAppleDisplay(displayID: CGDirectDisplayID) -> Bool {
    if #available(macOS 15.0, *) {
      if CGDisplayVendorNumber(displayID) != 1552, CGSIsHDRSupported(displayID), CGSIsHDREnabled(displayID) {
        return CGDisplayIsBuiltin(displayID) != 0
      }
    }
    var brightness: Float = -1
    let ret = DisplayServicesGetBrightness(displayID, &brightness)
    if ret == 0, brightness >= 0 { // If brightness read appears to be successful using DisplayServices then it should be an Apple display
      return true
    }
    return CGDisplayIsBuiltin(displayID) != 0 // If built-in display, it should be Apple
  }

  static func getByDisplayID(displayID: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { $0.displayID == displayID }
  }

  static func getDisplayRawNameByID(displayID: CGDirectDisplayID) -> String {
    let defaultName = ""
    if !DEBUG_MACOS10, #available(macOS 11.0, *) {
      if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?), let nameList = dictionary["DisplayProductName"] as? [String: String], let name = nameList["en_US"] ?? nameList.first?.value {
        return name
      }
    }
    if let screen = getByDisplayID(displayID: displayID) {
      return screen.displayName ?? defaultName
    }
    return defaultName
  }

  static func getDisplayNameByID(displayID: CGDirectDisplayID) -> String {
    let defaultName: String = NSLocalizedString("Unknown", comment: "Unknown display name")
    if !DEBUG_MACOS10, #available(macOS 11.0, *) {
      if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?), let nameList = dictionary["DisplayProductName"] as? [String: String], var name = nameList[Locale.current.identifier] ?? nameList["en_US"] ?? nameList.first?.value {
        if CGDisplayIsInHWMirrorSet(displayID) != 0 || CGDisplayIsInMirrorSet(displayID) != 0 {
          let mirroredDisplayID = CGDisplayMirrorsDisplay(displayID)
          if mirroredDisplayID != 0, let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(mirroredDisplayID)?.takeRetainedValue() as NSDictionary?), let nameList = dictionary["DisplayProductName"] as? [String: String], let mirroredName = nameList[Locale.current.identifier] ?? nameList["en_US"] ?? nameList.first?.value {
            name.append(" | " + mirroredName)
          }
        }
        return name
      }
    }
    if let screen = getByDisplayID(displayID: displayID) { // MARK: This, and NSScreen+Extension.swift will not be needed when we drop MacOS 10 support.

      if #available(macOS 10.15, *) {
        return screen.localizedName
      } else {
        return screen.displayName ?? defaultName
      }
    }
    return defaultName
  }
}
