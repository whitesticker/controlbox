import CoreAudio
import Foundation

extension Notification.Name {
  static let defaultOutputDeviceChanged = Notification.Name("controlbox.defaultOutputDeviceChanged")
}

/// The slice of SimplyCoreAudio the display engine reads: default output name and whether it has its own volume.
final class CoreAudioOutput {
  enum Scope {
    case output
  }

  struct Device {
    let id: AudioDeviceID

    var name: String {
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      )
      var name: Unmanaged<CFString>?
      var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
      guard AudioObjectGetPropertyData(self.id, &address, 0, nil, &size, &name) == noErr, let name else {
        return ""
      }
      return name.takeRetainedValue() as String
    }

    func canSetVirtualMainVolume(scope _: Scope) -> Bool {
      var address = AudioObjectPropertyAddress(
        mSelector: 0x766D_7663, // kAudioHardwareServiceDeviceProperty_VirtualMainVolume ('vmvc')
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
      )
      guard AudioObjectHasProperty(self.id, &address) else { return false }
      var settable: DarwinBoolean = false
      guard AudioObjectIsPropertySettable(self.id, &address, &settable) == noErr else { return false }
      return settable.boolValue
    }
  }

  private var listener: AudioObjectPropertyListenerBlock?

  init() {
    var address = Self.defaultOutputAddress
    let listener: AudioObjectPropertyListenerBlock = { _, _ in
      NotificationCenter.default.post(name: .defaultOutputDeviceChanged, object: nil)
    }
    self.listener = listener
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
  }

  var defaultOutputDevice: Device? {
    var address = Self.defaultOutputAddress
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
          deviceID != kAudioObjectUnknown else {
      return nil
    }
    return Device(id: deviceID)
  }

  private static var defaultOutputAddress: AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
  }
}
